import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:record/record.dart';

class FluteTrainerAutoScreen extends StatefulWidget {
  const FluteTrainerAutoScreen({super.key});

  @override
  State<FluteTrainerAutoScreen> createState() => _FluteTrainerAutoScreenState();
}

class _FluteTrainerAutoScreenState extends State<FluteTrainerAutoScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final PitchDetector _pitchDetector = PitchDetector();

  bool _isRecording = false;
  bool _isInitialized = false;
  bool _isInitializing = false;
  String _detectedNote = '--';
  double _currentFrequency = 0.0;
  String _feedbackText = 'اضغط على زر التسجيل للبدء';
  Color _feedbackColor = Colors.grey;
  Timer? _feedbackTimer;
  final List<double> _recentFrequencies = [];
  StreamSubscription<List<int>>? _recordingSubscription;

  // Note frequencies map - الترددات المرجعية للنغمات
  static const Map<String, double> noteFrequencies = {
    'C4': 261.63,
    'C#4': 277.18,
    'D4': 293.66,
    'D#4': 311.13,
    'E4': 329.63,
    'F4': 349.23,
    'F#4': 369.99,
    'G4': 392.00,
    'G#4': 415.30,
    'A4': 440.00,
    'A#4': 466.16,
    'B4': 493.88,
    'C5': 523.25,
    'C#5': 554.37,
    'D5': 587.33,
    'D#5': 622.25,
    'E5': 659.25,
    'F5': 698.46,
    'F#5': 739.99,
    'G5': 783.99,
    'G#5': 830.61,
    'A5': 880.00,
    'A#5': 932.33,
    'B5': 987.77,
    'C6': 1046.50,
  };

  // التسامح في التردد بالهرتز - تم تقليله للويب
  static const double tolerance = 12.0; // تم تقليله من 15 إلى 12
  static const int maxFrequencyHistory = 7; // زيادة العينات للاستقرار

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  Future<void> _initializeApp() async {
    if (_isInitializing) return;

    setState(() {
      _isInitializing = true;
      _feedbackText = 'جاري التهيئة...';
      _feedbackColor = Colors.orange;
    });

    await _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    try {
      // في الويب، استخدم طريقة مختلفة للأذونات
      if (kIsWeb) {
        await _initializeAudio();
      } else {
        final micStatus = await Permission.microphone.request();

        if (micStatus == PermissionStatus.granted) {
          await _initializeAudio();
        } else if (micStatus == PermissionStatus.denied) {
          setState(() {
            _feedbackText = 'تم رفض إذن الميكروفون. يرجى التفعيل من الإعدادات.';
            _feedbackColor = Colors.red;
            _isInitializing = false;
          });
        } else if (micStatus == PermissionStatus.permanentlyDenied) {
          setState(() {
            _feedbackText =
                'تم رفض إذن الميكروفون نهائياً. يرجى التفعيل من إعدادات الجهاز.';
            _feedbackColor = Colors.red;
            _isInitializing = false;
          });
          _showPermissionDialog();
        }
      }
    } catch (e) {
      print('Permission error: $e');
      setState(() {
        _feedbackText = 'خطأ في الأذونات: ${e.toString()}';
        _feedbackColor = Colors.red;
        _isInitializing = false;
      });
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('مطلوب إذن'),
          content: const Text(
            'يحتاج التطبيق إلى إذن الميكروفون لاكتشاف التردد. يرجى تفعيل إذن الميكروفون من إعدادات المتصفح.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
            if (!kIsWeb)
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openAppSettings();
                },
                child: const Text('فتح الإعدادات'),
              ),
          ],
        );
      },
    );
  }

  Future<void> _initializeAudio() async {
    try {
      // فحص إمكانية التسجيل
      if (await _audioRecorder.hasPermission()) {
        setState(() {
          _isInitialized = true;
          _isInitializing = false;
          _feedbackText = 'جاهز للبدء! اضغط على زر التسجيل';
          _feedbackColor = Colors.green;
        });
      } else {
        throw Exception('لا يوجد إذن للتسجيل');
      }
    } catch (e) {
      print('Failed to initialize audio: $e');
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _isInitializing = false;
          _feedbackText = 'فشل في تهيئة الميكروفون: ${e.toString()}';
          _feedbackColor = Colors.red;
        });
      }
    }
  }

  // دالة لتحديد النغمة الأقرب للتردد المكتشف - محسنة للويب
  String _getClosestNote(double frequency) {
    if (frequency <= 0 || frequency < 200 || frequency > 1200) return '--';

    String closestNote = '--';
    double minDifference = double.infinity;

    noteFrequencies.forEach((note, freq) {
      double difference = (frequency - freq).abs();
      if (difference < minDifference) {
        minDifference = difference;
        closestNote = note;
      }
    });

    // في الويب، تأكد من دقة النتيجة
    if (minDifference > 50) return '--'; // رفض النتائج البعيدة جداً

    return closestNote;
  }

  // حساب الفرق بالهرتز والسنت
  Map<String, dynamic> _calculateDifference(double currentFreq, String note) {
    if (currentFreq <= 0 || note == '--') {
      return {'hz': 0.0, 'cents': 0.0, 'isInTune': false};
    }

    final targetFreq = noteFrequencies[note]!;
    final hzDifference = currentFreq - targetFreq;
    final cents = 1200 * (math.log(currentFreq / targetFreq) / math.log(2));
    final isInTune = hzDifference.abs() <= tolerance;

    return {
      'hz': hzDifference,
      'cents': cents,
      'isInTune': isInTune,
    };
  }

  // دالة محسنة لتحويل البيانات للويب
  Stream<List<int>> _bufferedListStream<T>(
    Stream<T> source,
    int bufferSize,
  ) async* {
    List<int> buffer = [];

    await for (T item in source) {
      if (item is Uint8List) {
        // في الويب، تأكد من التحويل الصحيح
        List<int> convertedData = [];
        for (int i = 0; i < item.length; i += 2) {
          if (i + 1 < item.length) {
            // تحويل little-endian 16-bit PCM
            int sample = (item[i + 1] << 8) | item[i];
            // تحويل من unsigned إلى signed
            if (sample > 32767) sample -= 65536;
            convertedData.add(sample);
          }
        }
        buffer.addAll(convertedData);

        while (buffer.length >= bufferSize) {
          yield buffer.take(bufferSize).toList();
          buffer = buffer.skip(bufferSize).toList();
        }
      }
    }

    if (buffer.isNotEmpty) {
      yield buffer;
    }
  }

  Future<void> _startRecording() async {
    try {
      // إعدادات محسنة للويب
      final recordConfig = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        numChannels: 1,
        bitRate: kIsWeb ? 64000 : 128000, // تقليل bitRate للويب
        sampleRate: PitchDetector.DEFAULT_SAMPLE_RATE,
      );

      final recordStream = await _audioRecorder.startStream(recordConfig);

      // حجم buffer محسن للويب
      final bufferSize = kIsWeb 
          ? PitchDetector.DEFAULT_BUFFER_SIZE 
          : PitchDetector.DEFAULT_BUFFER_SIZE * 2;

      var audioSampleBufferedStream = _bufferedListStream(
        recordStream.map((event) => event),
        bufferSize,
      );

      _recordingSubscription = audioSampleBufferedStream.listen(
        (audioSample) async {
          if (!_isRecording) return;

          try {
            // تحويل محسن للويب
            Uint8List intBuffer;
            
            if (kIsWeb) {
              // في الويب، استخدم التحويل المباشر
              final bytes = <int>[];
              for (int sample in audioSample) {
                // تحويل من signed إلى unsigned 16-bit
                int unsignedSample = sample < 0 ? sample + 65536 : sample;
                bytes.add(unsignedSample & 0xFF);
                bytes.add((unsignedSample >> 8) & 0xFF);
              }
              intBuffer = Uint8List.fromList(bytes);
            } else {
              intBuffer = Uint8List.fromList(audioSample);
            }

            final detectedPitch = await _pitchDetector.getPitchFromIntBuffer(intBuffer);

            // فحص محسن للنتائج
            if (detectedPitch.pitched &&
                detectedPitch.pitch > 200 && // رفع الحد الأدنى
                detectedPitch.pitch < 1200 && // خفض الحد الأعلى
                !detectedPitch.pitch.isNaN &&
                !detectedPitch.pitch.isInfinite &&
                detectedPitch.pitch != 0.0) {
              
              _addFrequencyToHistory(detectedPitch.pitch);
              final smoothedFrequency = _getSmoothedFrequency();

              if (mounted && smoothedFrequency > 0) {
                setState(() {
                  _currentFrequency = smoothedFrequency;
                  _detectedNote = _getClosestNote(smoothedFrequency);
                  _updateFeedback();
                });
              }
            }
          } catch (e) {
            print('خطأ في معالجة الصوت: $e');
          }
        },
        onError: (error) {
          print('خطأ في التسجيل: $error');
          if (mounted) {
            setState(() {
              _feedbackText = 'خطأ في التسجيل: ${error.toString()}';
              _feedbackColor = Colors.red;
              _isRecording = false;
            });
          }
        },
      );

      setState(() {
        _isRecording = true;
        _feedbackText = 'استمع... اعزف أي نغمة';
        _feedbackColor = Colors.orange;
        _recentFrequencies.clear();
      });
    } catch (e) {
      print('خطأ في بدء التسجيل: $e');
      setState(() {
        _feedbackText = 'خطأ في بدء التسجيل: ${e.toString()}';
        _feedbackColor = Colors.red;
        _isRecording = false;
      });
    }
  }

  Future<void> _stopRecording() async {
    try {
      await _recordingSubscription?.cancel();
      await _audioRecorder.stop();

      setState(() {
        _isRecording = false;
        _feedbackText = 'تم إيقاف التسجيل';
        _feedbackColor = Colors.grey;
        _currentFrequency = 0.0;
        _detectedNote = '--';
        _recentFrequencies.clear();
        _feedbackTimer?.cancel();
      });
    } catch (e) {
      print('خطأ في إيقاف التسجيل: $e');
    }
  }

  void _addFrequencyToHistory(double frequency) {
    if (frequency > 0 && !frequency.isNaN && !frequency.isInfinite) {
      _recentFrequencies.add(frequency);
      if (_recentFrequencies.length > maxFrequencyHistory) {
        _recentFrequencies.removeAt(0);
      }
    }
  }

  // دالة محسنة للحصول على تردد مستقر
  double _getSmoothedFrequency() {
    if (_recentFrequencies.isEmpty) return 0.0;

    List<double> validFreqs = _recentFrequencies
        .where((f) => f > 0 && !f.isNaN && !f.isInfinite)
        .toList();

    if (validFreqs.isEmpty) return 0.0;
    if (validFreqs.length < 3) return validFreqs.last; // انتظار عينات كافية

    // استخدام median للتخلص من القيم الشاذة
    validFreqs.sort();
    int middle = validFreqs.length ~/ 2;
    
    if (validFreqs.length % 2 == 0) {
      return (validFreqs[middle - 1] + validFreqs[middle]) / 2;
    } else {
      return validFreqs[middle];
    }
  }

  void _updateFeedback() {
    if (_currentFrequency <= 0 || _detectedNote == '--') return;

    final difference = _calculateDifference(_currentFrequency, _detectedNote);
    final hzDiff = difference['hz'] as double;
    final cents = difference['cents'] as double;
    final isInTune = difference['isInTune'] as bool;

    if (isInTune) {
      _feedbackText = '🎯 ممتاز! النغمة مضبوطة تماماً';
      _feedbackColor = Colors.green;
    } else if (hzDiff > tolerance) {
      if (hzDiff > tolerance * 2) {
        _feedbackText = '📉 عالي جداً - قلل قوة النفخ';
      } else {
        _feedbackText = '📉 عالي قليلاً - اضبط الشفاه';
      }
      _feedbackColor = Colors.red;
    } else {
      if (hzDiff < -tolerance * 2) {
        _feedbackText = '📈 منخفض جداً - زد قوة النفخ';
      } else {
        _feedbackText = '📈 منخفض قليلاً - زد سرعة الهواء';
      }
      _feedbackColor = Colors.blue;
    }

    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isRecording) {
        setState(() {
          _feedbackText = 'استمع... اعزف أي نغمة';
          _feedbackColor = Colors.orange;
        });
      }
    });
  }

  void _toggleRecording() async {
    if (!_isInitialized) {
      if (!_isInitializing) {
        await _initializeApp();
      }
      return;
    }

    if (_isRecording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  @override
  Widget build(BuildContext context) {
    final difference = _calculateDifference(_currentFrequency, _detectedNote);
    final hzDiff = difference['hz'] as double;
    final cents = difference['cents'] as double;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('🎵 مدرب الناي ${kIsWeb ? "(ويب)" : ""}'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Box 1: النغمة المكتشفة
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text(
                      'النغمة المكتشفة',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _detectedNote,
                      style: const TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_currentFrequency.toStringAsFixed(2)} Hz',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Box 2: البعد عن التردد المطلوب
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    Text(
                      'انحراف التردد',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'بالهرتز',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${hzDiff.toStringAsFixed(2)} Hz',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: hzDiff.abs() <= tolerance 
                                      ? Colors.green 
                                      : hzDiff > 0 
                                          ? Colors.red 
                                          : Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          height: 40,
                          width: 1,
                          color: Colors.grey[300],
                        ),
                        Expanded(
                          child: Column(
                            children: [
                              Text(
                                'بالسنت',
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.grey[500],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '${cents.toStringAsFixed(0)} ¢',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: hzDiff.abs() <= tolerance 
                                      ? Colors.green 
                                      : hzDiff > 0 
                                          ? Colors.red 
                                          : Colors.blue,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // حالة النفخ (التعليق)
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              color: _feedbackColor.withOpacity(0.1),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  _feedbackText,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _feedbackColor,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

            const SizedBox(height: 30),

            // زر التسجيل/الإيقاف
            SizedBox(
              height: 60,
              child: ElevatedButton.icon(
                onPressed: _isInitializing ? null : _toggleRecording,
                icon: Icon(
                  _isRecording ? Icons.stop : Icons.mic,
                  size: 28,
                ),
                label: Text(
                  _isInitializing
                      ? 'جاري التحميل...'
                      : (_isRecording ? 'إيقاف التسجيل' : 'بدء التسجيل'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording ? Colors.red : Colors.green,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
              ),
            ),

            if (kIsWeb) ...[
              const SizedBox(height: 16),
              Text(
                'ملاحظة: في الويب، تأكد من السماح للميكروفون في المتصفح',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontStyle: FontStyle.italic,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _recordingSubscription?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }
}
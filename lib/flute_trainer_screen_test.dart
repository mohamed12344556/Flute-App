import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:record/record.dart';

class FluteTrainerTestScreen extends StatefulWidget {
  const FluteTrainerTestScreen({super.key});

  @override
  State<FluteTrainerTestScreen> createState() => _FluteTrainerTestScreenState();
}

class _FluteTrainerTestScreenState extends State<FluteTrainerTestScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final PitchDetector _pitchDetector = PitchDetector();

  bool _isRecording = false;
  bool _isInitialized = false;
  bool _isInitializing = false;
  String _detectedNote = '--';
  double _currentFrequency = 0.0;
  String _feedbackText = 'اضغط للبدء';
  Color _feedbackColor = Colors.grey;
  Timer? _feedbackTimer;
  Timer? _processingTimer;
  final List<double> _recentFrequencies = [];
  StreamSubscription<List<int>>? _recordingSubscription;

  // Buffer لتجميع البيانات الصوتية
  final List<int> _audioBuffer = [];
  static const int _targetBufferSize = PitchDetector.DEFAULT_BUFFER_SIZE * 2;

  // إضافة متغير لتتبع آخر تردد صالح
  double _lastValidFrequency = 0.0;
  DateTime _lastValidFrequencyTime = DateTime.now();

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

  static const int maxFrequencyHistory = 5;

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
            'يحتاج التطبيق إلى إذن الميكروفون لاكتشاف التردد. يرجى تفعيل إذن الميكروفون من إعدادات الجهاز.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إلغاء'),
            ),
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
      if (await _audioRecorder.hasPermission()) {
        setState(() {
          _isInitialized = true;
          _isInitializing = false;
          _feedbackText = 'جاهز للبدء!';
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

  Future<void> _startRecording() async {
    try {
      // تنظيف كامل للبيانات
      _cleanupAudioData();

      final recordStream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          numChannels: 1,
          bitRate: 128000,
          sampleRate: PitchDetector.DEFAULT_SAMPLE_RATE,
        ),
      );

      _recordingSubscription = recordStream.listen(
        (audioChunk) {
          if (!_isRecording) return;
          _audioBuffer.addAll(audioChunk);
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

      _processingTimer = Timer.periodic(
        const Duration(milliseconds: 1),
        (timer) {
          // التحقق من أن التسجيل ما زال نشطاً
          if (!_isRecording) {



            
            timer.cancel();
            return;
          }
          _processAudioBuffer();
        },
      );

      setState(() {
        _isRecording = true;
        _feedbackText = 'استمع...';
        _feedbackColor = Colors.orange;
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

  void _processAudioBuffer() async {
    if (!_isRecording || _audioBuffer.length < _targetBufferSize) {
      return;
    }

    try {
      final samplesToProcess = _audioBuffer.take(_targetBufferSize).toList();
      _audioBuffer.removeRange(
        0,
        math.min(_targetBufferSize, _audioBuffer.length),
      );

      final intBuffer = Uint8List.fromList(samplesToProcess);
      final detectedPitch = await _pitchDetector.getPitchFromIntBuffer(
        intBuffer,
      );

      if (detectedPitch.pitched &&
          detectedPitch.pitch > 80 &&
          detectedPitch.pitch < 1500 &&
          !detectedPitch.pitch.isNaN &&
          !detectedPitch.pitch.isInfinite) {
        
        // تحديث آخر تردد صالح والوقت
        _lastValidFrequency = detectedPitch.pitch;
        _lastValidFrequencyTime = DateTime.now();
        
        _addFrequencyToHistory(detectedPitch.pitch);
        final smoothedFrequency = _getSmoothedFrequency();

        if (mounted && smoothedFrequency > 0 && _isRecording) {
          setState(() {
            _currentFrequency = smoothedFrequency;
            _detectedNote = _getClosestNote(smoothedFrequency);
            _updateFeedback();
          });
        }
      } else {
        // إذا لم يتم اكتشاف تردد صالح لأكثر من ثانية واحدة، قم بإعادة تعيين القيم
        final timeSinceLastValid = DateTime.now().difference(_lastValidFrequencyTime).inMilliseconds;
        if (timeSinceLastValid > 1000 && _isRecording) {
          if (mounted) {
            setState(() {
              _currentFrequency = 0.0;
              _detectedNote = '--';
              _feedbackText = 'استمع...';
              _feedbackColor = Colors.orange;
            });
          }
        }
      }
    } catch (e) {
      print('خطأ في معالجة الصوت: $e');
    }
  }

  String _getClosestNote(double frequency) {
    if (frequency <= 0) return '--';

    String closestNote = 'C4';
    double minDifference = double.infinity;

    noteFrequencies.forEach((note, freq) {
      double difference = (frequency - freq).abs();
      if (difference < minDifference) {
        minDifference = difference;
        closestNote = note;
      }
    });

    return closestNote;
  }

  double _getFrequencyDifference() {
    if (_detectedNote == '--' || _currentFrequency <= 0) return 0.0;
    final targetFreq = noteFrequencies[_detectedNote]!;
    return _currentFrequency - targetFreq;
  }

  double _getCentsDifference() {
    if (_detectedNote == '--' || _currentFrequency <= 0) return 0.0;
    final targetFreq = noteFrequencies[_detectedNote]!;
    return 1200 * (math.log(_currentFrequency / targetFreq) / math.log(2));
  }

  Future<void> _stopRecording() async {
    try {
      // إيقاف التسجيل أولاً
      setState(() {
        _isRecording = false;
      });

      // إيقاف المؤقت
      _processingTimer?.cancel();
      _processingTimer = null;

      // إيقاف الاشتراك في التسجيل
      await _recordingSubscription?.cancel();
      _recordingSubscription = null;

      // إيقاف المسجل
      await _audioRecorder.stop();

      // تنظيف البيانات
      _cleanupAudioData();

      // إيقاف مؤقت التغذية الراجعة
      _feedbackTimer?.cancel();
      _feedbackTimer = null;

      setState(() {
        _feedbackText = 'تم إيقاف التسجيل';
        _feedbackColor = Colors.grey;
        _currentFrequency = 0.0;
        _detectedNote = '--';
      });

    } catch (e) {
      print('خطأ في إيقاف التسجيل: $e');
    }
  }

  void _cleanupAudioData() {
    _audioBuffer.clear();
    _recentFrequencies.clear();
    _lastValidFrequency = 0.0;
    _lastValidFrequencyTime = DateTime.now();
  }

  void _addFrequencyToHistory(double frequency) {
    if (frequency > 0 && !frequency.isNaN && !frequency.isInfinite) {
      _recentFrequencies.add(frequency);
      if (_recentFrequencies.length > maxFrequencyHistory) {
        _recentFrequencies.removeAt(0);
      }
    }
  }

  double _getSmoothedFrequency() {
    if (_recentFrequencies.isEmpty) return 0.0;

    List<double> validFreqs = _recentFrequencies
        .where((f) => f > 0 && !f.isNaN && !f.isInfinite)
        .toList();

    if (validFreqs.isEmpty) return 0.0;

    double sum = validFreqs.reduce((a, b) => a + b);
    return sum / validFreqs.length;
  }

  void _updateFeedback() {
    if (_currentFrequency <= 0 || _detectedNote == '--') {
      _feedbackText = 'استمع...';
      _feedbackColor = Colors.orange;
      return;
    }

    final cents = _getCentsDifference();

    if (cents.abs() <= 10) {
      // Very close in cents
      _feedbackText = '🎯 ممتاز! مضبوط تماماً';
      _feedbackColor = Colors.green;
    } else if (cents > 10) {
      if (cents > 30) {
        _feedbackText = '📉 عالي جداً - قلل قوة النفخ';
      } else {
        _feedbackText = '📉 عالي قليلاً - اضبط الشفاه';
      }
      _feedbackColor = Colors.red;
    } else {
      if (cents < -30) {
        _feedbackText = '📈 منخفض جداً - زد قوة النفخ';
      } else {
        _feedbackText = '📈 منخفض قليلاً - زد سرعة الهواء';
      }
      _feedbackColor = Colors.blue;
    }

    // إلغاء المؤقت السابق قبل إنشاء واحد جديد
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isRecording) {
        setState(() {
          _feedbackText = 'استمع...';
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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('🎵 مدرب الناي'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Box الأول - النغمة المكتشفة
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Text(
                      'النغمة المكتشفة',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
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
                      style: const TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Box التاني - المسافة من النغمة المكتشفة
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Text(
                      'دقة العزف',
                      style: TextStyle(
                        fontSize: 16,
                        color: Colors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        Column(
                          children: [
                            const Text(
                              'الفرق بالهرتز',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_getFrequencyDifference().toStringAsFixed(2)} Hz',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _getFrequencyDifference().abs() <= 15
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        Container(
                          height: 40,
                          width: 1,
                          color: Colors.grey[300],
                        ),
                        Column(
                          children: [
                            const Text(
                              'الفرق بالسنت',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.grey,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${_getCentsDifference().toStringAsFixed(0)} ¢',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: _getCentsDifference().abs() <= 10
                                    ? Colors.green
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // حالة التغذية الراجعة
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
            ElevatedButton.icon(
              onPressed: _isInitializing ? null : _toggleRecording,
              icon: Icon(_isRecording ? Icons.stop : Icons.mic, size: 28),
              label: Text(
                _isInitializing
                    ? 'جاري التحميل...'
                    : (_isRecording ? 'إيقاف التسجيل' : 'بدء التسجيل'),
                style: const TextStyle(fontSize: 18),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _processingTimer?.cancel();
    _recordingSubscription?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }
}
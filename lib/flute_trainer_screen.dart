import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:record/record.dart';

class FluteTrainerScreen extends StatefulWidget {
  const FluteTrainerScreen({super.key});

  @override
  State<FluteTrainerScreen> createState() => _FluteTrainerScreenState();
}

class _FluteTrainerScreenState extends State<FluteTrainerScreen> {
  final AudioRecorder _audioRecorder = AudioRecorder();
  final PitchDetector _pitchDetector = PitchDetector();

  bool _isRecording = false;
  bool _isInitialized = false;
  bool _isInitializing = false;
  String _selectedNote = 'C4';
  double _currentFrequency = 0.0;
  String _feedbackText = 'اختر نغمة وابدأ التسجيل';
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

  // مسارات الصور للنغمات - يجب إضافة الصور في مجلد assets/images/
  static const Map<String, String> noteImages = {
    'C4': 'assets/images/c4.png',
    'C#4': 'assets/images/c_sharp_4.jpg',
    'D4': 'assets/images/d4.png',
    'D#4': 'assets/images/d_sharp_4.png',
    'E4': 'assets/images/e4.png',
    'F4': 'assets/images/f4.png',
    'F#4': 'assets/images/f_sharp_4.png',
    'G4': 'assets/images/g4.png',
    'G#4': 'assets/images/g_sharp_4.png',
    'A4': 'assets/images/a4.png',
    'A#4': 'assets/images/a_sharp_4.png',
    'B4': 'assets/images/b4.png',
    'C5': 'assets/images/c5.png',
    'C#5': 'assets/images/c_sharp_5.png',
    'D5': 'assets/images/d5.png',
    'D#5': 'assets/images/d_sharp_5.png',
    'E5': 'assets/images/e5.png',
    'F5': 'assets/images/f5.png',
    'F#5': 'assets/images/f_sharp_5.png',
    'G5': 'assets/images/g5.png',
    'G#5': 'assets/images/g_sharp_5.png',
    'A5': 'assets/images/a5.png',
    'A#5': 'assets/images/a_sharp_5.png',
    'B5': 'assets/images/b5.png',
    'C6': 'assets/images/c6.png',
  };

  // التسامح في التردد بالهرتز
  static const double tolerance = 15.0;
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
      // فحص إمكانية التسجيل
      if (await _audioRecorder.hasPermission()) {
        setState(() {
          _isInitialized = true;
          _isInitializing = false;
          _feedbackText = 'جاهز للبدء! اختر نغمة واضغط تسجيل';
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

  // دالة لتحويل المخزن المؤقت والتحكم في التدفق
  Stream<List<int>> _bufferedListStream<T>(
    Stream<T> source,
    int bufferSize,
  ) async* {
    List<int> buffer = [];

    await for (T item in source) {
      if (item is Uint8List) {
        buffer.addAll(item);

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
      // بدء التسجيل مع التكوين الصحيح
      final recordStream = await _audioRecorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          numChannels: 1,
          bitRate: 128000,
          sampleRate: PitchDetector.DEFAULT_SAMPLE_RATE,
        ),
      );

      // تحويل التدفق وتجميعه
      var audioSampleBufferedStream = _bufferedListStream(
        recordStream.map((event) => event),
        PitchDetector.DEFAULT_BUFFER_SIZE * 2,
      );

      // الاستماع للتدفق ومعالجة البيانات
      _recordingSubscription = audioSampleBufferedStream.listen(
        (audioSample) async {
          if (!_isRecording) return;

          try {
            final intBuffer = Uint8List.fromList(audioSample);

            // استخدام getPitchFromIntBuffer بدلاً من getPitchFromFloatBuffer
            final detectedPitch = await _pitchDetector.getPitchFromIntBuffer(
              intBuffer,
            );

            if (detectedPitch.pitched &&
                detectedPitch.pitch > 80 &&
                detectedPitch.pitch < 1500 &&
                !detectedPitch.pitch.isNaN &&
                !detectedPitch.pitch.isInfinite) {
              _addFrequencyToHistory(detectedPitch.pitch);
              final smoothedFrequency = _getSmoothedFrequency();

              if (mounted && smoothedFrequency > 0) {
                setState(() {
                  _currentFrequency = smoothedFrequency;
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
        _feedbackText = 'استمع... اعزف $_selectedNote';
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

  double _getSmoothedFrequency() {
    if (_recentFrequencies.isEmpty) return 0.0;

    // استخدام المتوسط للاستقرار
    List<double> validFreqs = _recentFrequencies
        .where((f) => f > 0 && !f.isNaN && !f.isInfinite)
        .toList();

    if (validFreqs.isEmpty) return 0.0;

    double sum = validFreqs.reduce((a, b) => a + b);
    return sum / validFreqs.length;
  }

  void _updateFeedback() {
    if (_currentFrequency <= 0) return;

    final targetFreq = noteFrequencies[_selectedNote]!;
    final difference = _currentFrequency - targetFreq;
    final cents =
        1200 * (math.log(_currentFrequency / targetFreq) / math.log(2));

    if (difference.abs() <= tolerance) {
      _feedbackText =
          '🎯 ممتاز! مضبوط تماماً (${cents.toStringAsFixed(0)} سنت)';
      _feedbackColor = Colors.green;
    } else if (difference > tolerance) {
      if (difference > tolerance * 2) {
        _feedbackText =
            '📉 عالي جداً - قلل قوة النفخ (${cents.toStringAsFixed(0)} سنت)';
      } else {
        _feedbackText =
            '📉 عالي قليلاً - اضبط الشفاه (${cents.toStringAsFixed(0)} سنت)';
      }
      _feedbackColor = Colors.red;
    } else {
      if (difference < -tolerance * 2) {
        _feedbackText =
            '📈 منخفض جداً - زد قوة النفخ (${cents.toStringAsFixed(0)} سنت)';
      } else {
        _feedbackText =
            '📈 منخفض قليلاً - زد سرعة الهواء (${cents.toStringAsFixed(0)} سنت)';
      }
      _feedbackColor = Colors.blue;
    }

    // مسح التعليقات تلقائياً بعد 3 ثوانٍ من عدم وجود إدخال
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isRecording) {
        setState(() {
          _feedbackText = 'استمع... اعزف $_selectedNote';
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

  // Widget لعرض صورة النغمة
  Widget _buildNoteImage() {
    final imagePath = noteImages[_selectedNote];

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Container(
        height: 150,
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              'النغمة المطلوبة: $_selectedNote',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: imagePath != null
                  ? Image.asset(
                      imagePath,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.music_note,
                                size: 40,
                                color: Colors.grey,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                _selectedNote,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.music_note,
                            size: 40,
                            color: Colors.grey,
                          ),
                          const SizedBox(height: 5),
                          Text(
                            _selectedNote,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
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
            // اختيار النغمة المطلوبة
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const Text(
                      'اختر النغمة المطلوبة',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedNote,
                      decoration: InputDecoration(
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      items: noteFrequencies.keys.map((note) {
                        return DropdownMenuItem<String>(
                          value: note,
                          child: Text(
                            '$note (${noteFrequencies[note]!.toStringAsFixed(2)} Hz)',
                          ),
                        );
                      }).toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedNote = value!;
                          _feedbackText = 'تم تغيير النغمة إلى $_selectedNote';
                          _feedbackColor = Colors.grey;
                          _currentFrequency = 0.0;
                          _recentFrequencies.clear();
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 20),

            // عرض صورة النغمة المختارة
            _buildNoteImage(),

            const SizedBox(height: 20),

            // التردد الحالي والمطلوب
            Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    Text(
                      'التردد الحالي',
                      style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${_currentFrequency.toStringAsFixed(2)} Hz',
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'المطلوب: ${noteFrequencies[_selectedNote]!.toStringAsFixed(2)} Hz',
                      style: TextStyle(fontSize: 14, color: Colors.grey[600]),
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

            // زر التسجيل/الإيقاף فقط
            ElevatedButton.icon(
              onPressed: _isInitializing ? null : _toggleRecording,
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(
                _isInitializing
                    ? 'جاري التحميل...'
                    : (_isRecording ? 'إيقاف' : 'تسجيل'),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
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
    _recordingSubscription?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }
}

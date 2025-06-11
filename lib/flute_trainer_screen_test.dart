import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:audio_streamer/audio_streamer.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';

class FluteTrainerTestScreen extends StatefulWidget {
  const FluteTrainerTestScreen({super.key});

  @override
  State<FluteTrainerTestScreen> createState() => _FluteTrainerTestScreenState();
}

class _FluteTrainerTestScreenState extends State<FluteTrainerTestScreen> {
  final PitchDetector _pitchDetector = PitchDetector();

  bool _isRecording = false;
  bool _isInitialized = false;
  bool _isInitializing = false;
  String _detectedNote = '--';
  double _currentFrequency = 0.0;
  String _feedbackText = 'اضغط للبدء';
  Color _feedbackColor = Colors.grey;
  Timer? _feedbackTimer;
  Timer? _analysisTimer;
  StreamSubscription<List<double>>? _audioSubscription;

  // Buffer لتجميع البيانات الصوتية
  final List<double> _audioBuffer = [];
  int? _sampleRate;

  // متغيرات التحكم في التوقيت
  static const int _analysisIntervalMs = 100; // 100 ميلي ثانية
  static const int _bufferSizeMs = 300; // زيادة حجم البافر لتحليل أفضل

  // للتتبع
  double _lastValidFrequency = 0.0;
  DateTime _lastValidFrequencyTime = DateTime.now();
  final List<double> _recentFrequencies = [];

  // Note frequencies map - تم تحديث الترددات لتكون أكثر دقة
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
    'C#6': 1108.73,
    'D6': 1174.66,
  };

  static const int maxFrequencyHistory =
      7; // زيادة التاريخ للحصول على نتائج أكثر استقراراً

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
      // تعيين معدل عينات أعلى للحصول على دقة أفضل
      AudioStreamer().sampleRate = 44100; // معدل عينات قياسي عالي الجودة

      setState(() {
        _isInitialized = true;
        _isInitializing = false;
        _feedbackText = 'جاهز للبدء!';
        _feedbackColor = Colors.green;
      });
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

  /// Callback لاستقبال البيانات الصوتية
  void _onAudio(List<double> buffer) async {
    if (!_isRecording) return;

    // إضافة البيانات الجديدة للبافر
    _audioBuffer.addAll(buffer);

    // الحصول على معدل العينات إذا لم يكن معروفاً
    _sampleRate ??= await AudioStreamer().actualSampleRate;
  }

  /// Callback للأخطاء
  void _handleError(Object error) {
    setState(() => _isRecording = false);
    print('Audio streaming error: $error');
    if (mounted) {
      setState(() {
        _feedbackText = 'خطأ في التسجيل: ${error.toString()}';
        _feedbackColor = Colors.red;
      });
    }
  }

  Future<void> _startRecording() async {
    try {
      // تنظيف البيانات
      _cleanupAudioData();

      // بدء الاستماع للصوت
      _audioSubscription = AudioStreamer().audioStream.listen(
        _onAudio,
        onError: _handleError,
      );

      // بدء مؤقت التحليل كل 100ms
      _analysisTimer = Timer.periodic(
        Duration(milliseconds: _analysisIntervalMs),
        (timer) {
          if (!_isRecording) {
            timer.cancel();
            return;
          }
          _analyzeAudio();
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

  void _analyzeAudio() async {
    if (!_isRecording || _sampleRate == null || _audioBuffer.isEmpty) {
      return;
    }

    try {
      // حساب حجم البافر المطلوب للتحليل
      final bufferSizeSamples = (_sampleRate! * _bufferSizeMs / 1000).round();

      if (_audioBuffer.length < bufferSizeSamples) {
        return; // لا توجد بيانات كافية للتحليل
      }

      // أخذ البيانات المطلوبة للتحليل
      final samplesToAnalyze = _audioBuffer.take(bufferSizeSamples).toList();

      // إزالة البيانات القديمة
      final samplesToRemove = (bufferSizeSamples * 0.5).round();
      if (_audioBuffer.length >= samplesToRemove) {
        _audioBuffer.removeRange(0, samplesToRemove);
      }

      // تحويل البيانات لتنسيق مناسب للـ pitch detector - تم إصلاح التحويل
      final intBuffer = _convertToInt16Buffer(samplesToAnalyze);

      // تحليل التردد مع معدل العينات الصحيح
      final detectedPitch = await _pitchDetector.getPitchFromIntBuffer(
        intBuffer,
        // sampleRate: _sampleRate!,
      );

      // تحسين شروط التحقق من صحة التردد
      if (detectedPitch.pitched &&
          detectedPitch.pitch > 200 && // رفع الحد الأدنى
          detectedPitch.pitch < 1200 && // تقليل الحد الأعلى
          !detectedPitch.pitch.isNaN &&
          !detectedPitch.pitch.isInfinite) {
        // تحديث آخر تردد صالح
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
        // إذا لم يتم اكتشاف تردد صالح لأكثر من ثانية واحدة
        final timeSinceLastValid = DateTime.now()
            .difference(_lastValidFrequencyTime)
            .inMilliseconds;
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
      print('خطأ في تحليل الصوت: $e');
    }
  }

  /// تحويل البيانات من double إلى Uint8List بطريقة صحيحة للـ 16-bit PCM
  Uint8List _convertToInt16Buffer(List<double> audioData) {
    final samples = <int>[];

    for (double sample in audioData) {
      // تحويل من [-1.0, 1.0] إلى [-32768, 32767] للـ 16-bit signed PCM
      int intSample = (sample.clamp(-1.0, 1.0) * 32767).round();

      // إضافة كـ little-endian 16-bit signed integer
      samples.add(intSample & 0xFF); // البايت الأقل أهمية
      samples.add((intSample >> 8) & 0xFF); // البايت الأكثر أهمية
    }

    return Uint8List.fromList(samples);
  }

  String _getClosestNote(double frequency) {
    if (frequency <= 0) return '--';

    String closestNote = 'C4';
    double minDifference = double.infinity;

    // البحث عن أقرب نغمة بدقة أكبر
    noteFrequencies.forEach((note, freq) {
      double difference = (frequency - freq).abs();
      if (difference < minDifference) {
        minDifference = difference;
        closestNote = note;
      }
    });

    // التحقق من أن الفرق ليس كبيراً جداً
    final targetFreq = noteFrequencies[closestNote]!;
    final percentageDiff = (frequency - targetFreq).abs() / targetFreq * 100;

    // إذا كان الفرق أكبر من 12% (تقريباً نصف نغمة) فقد تكون هناك مشكلة
    if (percentageDiff > 12) {
      print(
        'تحذير: فرق كبير في التردد - المكتشف: $frequency Hz، المتوقع: $targetFreq Hz',
      );
    }

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
      setState(() {
        _isRecording = false;
      });

      // إيقاف المؤقتات
      _analysisTimer?.cancel();
      _analysisTimer = null;
      _feedbackTimer?.cancel();
      _feedbackTimer = null;

      // إيقاف الاشتراك في الصوت
      await _audioSubscription?.cancel();
      _audioSubscription = null;

      // تنظيف البيانات
      _cleanupAudioData();

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

    // استخدام الوسيط بدلاً من المتوسط لتقليل تأثير القيم الشاذة
    validFreqs.sort();
    if (validFreqs.length % 2 == 0) {
      return (validFreqs[validFreqs.length ~/ 2 - 1] +
              validFreqs[validFreqs.length ~/ 2]) /
          2;
    } else {
      return validFreqs[validFreqs.length ~/ 2];
    }
  }

  void _updateFeedback() {
    if (_currentFrequency <= 0 || _detectedNote == '--') {
      _feedbackText = 'استمع...';
      _feedbackColor = Colors.orange;
      return;
    }

    final cents = _getCentsDifference();

    if (cents.abs() <= 10) {
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
            // معلومات التحليل
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    Column(
                      children: [
                        const Text(
                          'معدل التحليل',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          '${_analysisIntervalMs}ms',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text(
                          'معدل العينات',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          '${_sampleRate ?? "---"} Hz',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      children: [
                        const Text(
                          'حجم البافر',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          '${_bufferSizeMs}ms',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // النغمة المكتشفة
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

            // دقة العزف
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

            // التغذية الراجعة
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

            // زر التسجيل
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
    _analysisTimer?.cancel();
    _audioSubscription?.cancel();
    super.dispose();
  }
}

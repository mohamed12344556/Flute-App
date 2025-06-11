// Automatic FlutterFlow imports
// Custom imports
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:pitch_detector_dart/pitch_detector.dart';
import 'package:record/record.dart';

import '/backend/schema/structs/index.dart';
import '/custom_code/actions/index.dart';
import '/custom_code/actions/index.dart'; // Imports custom actions
// Begin custom widget code
// DO NOT REMOVE OR MODIFY THE CODE ABOVE!

import '/custom_code/widgets/index.dart';
import '/custom_code/widgets/index.dart'; // Imports other custom widgets
import '/flutter_flow/custom_functions.dart'; // Imports custom functions
import '/flutter_flow/flutter_flow_theme.dart';
import '/flutter_flow/flutter_flow_util.dart';
import '/flutter_flow/flutter_flow_widgets.dart';

class TunerTestWidget extends StatefulWidget {
  const TunerTestWidget({super.key, this.width, this.height});

  final double? width;
  final double? height;

  @override
  _TunerTestWidgetState createState() => _TunerTestWidgetState();
}

class _TunerTestWidgetState extends State<TunerTestWidget> {
  // كاشف درجة الصوت
  final PitchDetector _pitchDetector = PitchDetector();

  // مسجل الصوت الجديد
  final AudioRecorder _audioRecorder = AudioRecorder();

  // التحقق من المنصة
  bool get isWeb => kIsWeb;

  // متغيرات حالة التطبيق
  bool _isRecording = false;
  bool _isInitialized = false;
  bool _isInitializing = false;

  // متغيرات عرض البيانات
  String _detectedNote = '--';
  double _currentFrequency = 0.0;
  String _feedbackText = 'اضغط للبدء';
  Color _feedbackColor = Colors.grey;

  // المؤقتات والاشتراكات
  Timer? _feedbackTimer;
  Timer? _analysisTimer;
  StreamSubscription<Uint8List>? _audioSubscription;

  // متغيرات معالجة الصوت
  final List<double> _audioBuffer = [];

  // إعدادات محسنة للويب
  static const int _sampleRate = 44100; // توحيد المعدل لكل المنصات
  // تحسين 2: إعدادات تحليل موحدة
  static const int _analysisIntervalMs = 50; // نفس التوقيت
  static const int _bufferSizeMs = 200; // نفس حجم البافر
  static const int _minBufferSizeMs = 100; // نفس الحد الأدنى

  // متغيرات التحكم في الأداء
  DateTime _lastAnalysisTime = DateTime.now();
  bool _isAnalyzing = false;

  // متغيرات تنعيم النتائج المحسنة للويب
  double _lastValidFrequency = 0.0;
  DateTime _lastValidFrequencyTime = DateTime.now();
  final List<double> _recentFrequencies = [];
  final List<double> _rawFrequencies = []; // للتنعيم الإضافي

  // خريطة النغمات وترددها المحسنة
  static const Map<String, double> noteFrequencies = {
    'C2': 65.41,
    'C#2': 69.30,
    'D2': 73.42,
    'D#2': 77.78,
    'E2': 82.41,
    'F2': 87.31,
    'F#2': 92.50,
    'G2': 98.00,
    'G#2': 103.83,
    'A2': 110.00,
    'A#2': 116.54,
    'B2': 123.47,
    'C3': 130.81,
    'C#3': 138.59,
    'D3': 146.83,
    'D#3': 155.56,
    'E3': 164.81,
    'F3': 174.61,
    'F#3': 185.00,
    'G3': 196.00,
    'G#3': 207.65,
    'A3': 220.00,
    'A#3': 233.08,
    'B3': 246.94,
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
    'D#6': 1244.51,
    'E6': 1318.51,
    'F6': 1396.91,
  };

  // تحسين 3: إزالة المعالجة المختلفة للويب
  static const int maxFrequencyHistory = 7; // نفس حجم التاريخ

  @override
  void initState() {
    super.initState();
    _initializeApp();
  }

  /// تهيئة التطبيق وطلب الأذونات اللازمة
  Future<void> _initializeApp() async {
    if (_isInitializing) return;

    setState(() {
      _isInitializing = true;
      _feedbackText = 'جاري التهيئة...';
      _feedbackColor = Colors.orange;
    });

    await _requestPermissions();
  }

  /// طلب أذونات الميكروفون
  Future<void> _requestPermissions() async {
    try {
      bool hasPermission = false;

      if (isWeb) {
        // للويب: محاولة متعددة للحصول على الإذن
        hasPermission = await _audioRecorder.hasPermission();
        if (!hasPermission) {
          setState(() {
            _feedbackText = 'يرجى السماح لاستخدام الميكروفون في المتصفح';
            _feedbackColor = Colors.orange;
          });

          // انتظار قليل قبل المحاولة مرة أخرى
          await Future.delayed(Duration(milliseconds: 500));
          hasPermission = await _tryWebPermission();
        }
      } else {
        final micStatus = await Permission.microphone.request();
        hasPermission = micStatus == PermissionStatus.granted;
      }

      if (hasPermission) {
        await _initializeAudio();
      } else {
        setState(() {
          _feedbackText = isWeb
              ? 'يرجى السماح لاستخدام الميكروفون وإعادة المحاولة'
              : 'تم رفض إذن الميكروفون';
          _feedbackColor = Colors.red;
          _isInitializing = false;
        });
      }
    } catch (e) {
      setState(() {
        _feedbackText = 'خطأ في الأذونات - يرجى إعادة المحاولة';
        _feedbackColor = Colors.red;
        _isInitializing = false;
      });
    }
  }

  /// محاولة الحصول على إذن الويب
  Future<bool> _tryWebPermission() async {
    try {
      // محاولة إنشاء stream للاختبار
      const testConfig = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 44100,
        numChannels: 1,
      );

      final stream = await _audioRecorder.startStream(testConfig);
      await stream.first.timeout(Duration(seconds: 2));
      await _audioRecorder.stop();

      return true;
    } catch (e) {
      return false;
    }
  }

  /// تهيئة إعدادات الصوت
  Future<void> _initializeAudio() async {
    try {
      setState(() {
        _isInitialized = true;
        _isInitializing = false;
        _feedbackText = 'جاهز للبدء!';
        _feedbackColor = Colors.green;
      });
    } catch (e) {
      setState(() {
        _isInitialized = false;
        _isInitializing = false;
        _feedbackText = 'فشل في تهيئة الميكروفون';
        _feedbackColor = Colors.red;
      });
    }
  }

  /// معالج استقبال البيانات الصوتية
  void _onAudio(Uint8List audioData) {
    if (!_isRecording) return;

    List<double> audioDoubles = _convertToDoubleBuffer(audioData);
    _audioBuffer.addAll(audioDoubles);

    // تحليل فوري للويب مع تأخير أقل
    if (isWeb) {
      _tryImmediateAnalysis();
    }
  }

  /// محاولة التحليل الفوري
  void _tryImmediateAnalysis() {
    final now = DateTime.now();
    final timeSinceLastAnalysis = now
        .difference(_lastAnalysisTime)
        .inMilliseconds;
    final minInterval = isWeb ? 50 : 30; // فترة أطول للويب

    if (timeSinceLastAnalysis >= minInterval &&
        !_isAnalyzing &&
        _hasEnoughDataForAnalysis()) {
      _analyzeAudio();
    }
  }

  /// فحص توفر بيانات كافية للتحليل
  bool _hasEnoughDataForAnalysis() {
    final minBufferSizeSamples = (_sampleRate * _minBufferSizeMs / 1000)
        .round();
    return _audioBuffer.length >= minBufferSizeSamples;
  }

  /// تحويل البيانات الصوتية إلى تنسيق double محسن للويب
  /// تحسين 5: معالجة موحدة للبيانات الصوتية
  List<double> _convertToDoubleBuffer(Uint8List audioData) {
    List<double> result = [];

    // معالجة موحدة لجميع المنصات
    for (int i = 0; i < audioData.length; i += 2) {
      if (i + 1 < audioData.length) {
        // قراءة little-endian 16-bit
        int sample = audioData[i] | (audioData[i + 1] << 8);
        if (sample > 32767) sample -= 65536;

        // تطبيع مع تحسين الدقة
        double normalizedSample = sample / 32768.0;

        // مرشح بسيط لإزالة الضوضاء المنخفضة
        if (normalizedSample.abs() > 0.001) {
          // عتبة ضوضاء منخفضة
          result.add(normalizedSample);
        }
      }
    }

    return result;
  }

  /// بدء عملية التسجيل والتحليل الصوتي
  Future<void> _startRecording() async {
    try {
      _cleanupAudioData();

      // إعدادات موحدة لجميع المنصات
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        bitRate: 128000, // معدل بت موحد
      );

      final stream = await _audioRecorder.startStream(config);

      _audioSubscription = stream.listen(
        _onAudio,
        onError: (error) {
          print('خطأ في التسجيل: $error');
          _handleRecordingError();
        },
      );

      // مؤقت موحد
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
      _handleRecordingError();
    }
  }

  /// تحسين 6: تحليل صوتي محسن للويب
  void _analyzeAudio() async {
    if (!_isRecording || _audioBuffer.isEmpty || _isAnalyzing) {
      return;
    }

    _isAnalyzing = true;
    _lastAnalysisTime = DateTime.now();

    try {
      final bufferSizeSamples = (_sampleRate * _bufferSizeMs / 1000).round();

      if (_audioBuffer.length < bufferSizeSamples) {
        _isAnalyzing = false;
        return;
      }

      final samplesToAnalyze = _audioBuffer.take(bufferSizeSamples).toList();

      // إزالة موحدة للبيانات المستخدمة
      final samplesToRemove = (bufferSizeSamples * 0.6).round();
      if (_audioBuffer.length >= samplesToRemove) {
        _audioBuffer.removeRange(0, samplesToRemove);
      }

      // تحسين 7: فلترة أفضل للبيانات
      List<double> filteredSamples = _improvedAudioFilter(samplesToAnalyze);

      final intBuffer = _convertToInt16Buffer(filteredSamples);
      final detectedPitch = await _pitchDetector.getPitchFromIntBuffer(
        intBuffer,
      );

      // معايير موحدة لجميع المنصات
      const double minFreq = 80.0;
      const double maxFreq = 2000.0;

      if (detectedPitch.pitched &&
          detectedPitch.pitch >= minFreq &&
          detectedPitch.pitch <= maxFreq &&
          !detectedPitch.pitch.isNaN &&
          !detectedPitch.pitch.isInfinite) {
        // تحسين 8: فلترة تردد أفضل
        if (_isValidFrequency(detectedPitch.pitch)) {
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
        }
      } else {
        _handleNoSignal();
      }
    } catch (e) {
      print('خطأ في تحليل الصوت: $e');
    } finally {
      _isAnalyzing = false;
    }
  }

  /// تحسين 9: فلتر صوتي محسن
  List<double> _improvedAudioFilter(List<double> samples) {
    if (samples.length < 3) return samples;

    List<double> filtered = [];

    // مرشح متوسط متحرك بسيط
    for (int i = 0; i < samples.length; i++) {
      if (i == 0 || i == samples.length - 1) {
        filtered.add(samples[i]);
      } else {
        // متوسط العينة مع الجيران
        double avg = (samples[i - 1] + samples[i] + samples[i + 1]) / 3;
        filtered.add(avg);
      }
    }

    return filtered;
  }

  /// تحسين 10: فحص صحة التردد
  bool _isValidFrequency(double frequency) {
    // فحص الاستقرار مع الترددات السابقة
    if (_recentFrequencies.length >= 2) {
      final lastFreq = _recentFrequencies.last;
      final deviation = (frequency - lastFreq).abs() / lastFreq;

      // رفض التغيرات الكبيرة المفاجئة
      if (deviation > 0.15) {
        return false;
      }
    }

    return true;
  }

  /// تحسين 11: معالجة عدم وجود إشارة
  void _handleNoSignal() {
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

  /// تحسين 12: معالجة أخطاء التسجيل
  void _handleRecordingError() {
    setState(() {
      _feedbackText = 'خطأ في التسجيل - يرجى إعادة المحاولة';
      _feedbackColor = Colors.red;
      _isRecording = false;
    });
  }

  /// تطبيق مرشح تمرير عالي بسيط للويب
  List<double> _applyHighPassFilter(List<double> samples) {
    if (samples.length < 2) return samples;

    List<double> filtered = [samples[0]];
    double alpha = 0.95; // معامل المرشح

    for (int i = 1; i < samples.length; i++) {
      double filteredSample =
          alpha * (filtered[i - 1] + samples[i] - samples[i - 1]);
      filtered.add(filteredSample);
    }

    return filtered;
  }

  /// تحويل البيانات الصوتية إلى تنسيق Int16
  Uint8List _convertToInt16Buffer(List<double> audioData) {
    final samples = <int>[];
    for (double sample in audioData) {
      int intSample = (sample.clamp(-1.0, 1.0) * 32767).round();
      samples.add(intSample & 0xFF);
      samples.add((intSample >> 8) & 0xFF);
    }
    return Uint8List.fromList(samples);
  }

  /// العثور على أقرب نغمة موسيقية للتردد المكتشف مع تحسين للويب
  String _getClosestNote(double frequency) {
    if (frequency <= 0) return '--';

    String closestNote = 'A4';
    double minDifference = double.infinity;

    noteFrequencies.forEach((note, freq) {
      double difference = (frequency - freq).abs();
      if (difference < minDifference) {
        minDifference = difference;
        closestNote = note;
      }
    });

    // للويب: تحقق إضافي من دقة التطابق
    if (isWeb) {
      final targetFreq = noteFrequencies[closestNote]!;
      final percentDifference = (frequency - targetFreq).abs() / targetFreq;

      // إذا كان الفرق كبير جداً، لا تعرض النغمة
      if (percentDifference > 0.2) {
        return '--';
      }
    }

    return closestNote;
  }

  /// حساب الفرق بالسنت بين التردد المكتشف والنغمة المستهدفة
  double _getCentsDifference() {
    if (_detectedNote == '--' || _currentFrequency <= 0) return 0.0;
    final targetFreq = noteFrequencies[_detectedNote];
    if (targetFreq == null) return 0.0;

    return 1200 * (math.log(_currentFrequency / targetFreq) / math.log(2));
  }

  /// إيقاف التسجيل وتنظيف الموارد
  Future<void> _stopRecording() async {
    try {
      setState(() => _isRecording = false);
      _analysisTimer?.cancel();
      _analysisTimer = null;
      _feedbackTimer?.cancel();
      _feedbackTimer = null;
      await _audioSubscription?.cancel();
      _audioSubscription = null;

      try {
        await _audioRecorder.stop();
      } catch (e) {
        print('خطأ في إيقاف المسجل: $e');
      }

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

  /// تنظيف البيانات الصوتية والمتغيرات
  void _cleanupAudioData() {
    _audioBuffer.clear();
    _recentFrequencies.clear();
    _rawFrequencies.clear();
    _lastValidFrequency = 0.0;
    _lastValidFrequencyTime = DateTime.now();
    _lastAnalysisTime = DateTime.now();
    _isAnalyzing = false;
  }

  /// إضافة تردد جديد لتاريخ الترددات للتنعيم
  void _addFrequencyToHistory(double frequency) {
    if (frequency > 0 && !frequency.isNaN && !frequency.isInfinite) {
      _recentFrequencies.add(frequency);
      if (_recentFrequencies.length > maxFrequencyHistory) {
        _recentFrequencies.removeAt(0);
      }
    }
  }

  /// تحسين 13: تنعيم موحد للترددات
  double _getSmoothedFrequency() {
    if (_recentFrequencies.isEmpty) return 0.0;

    List<double> validFreqs = _recentFrequencies
        .where((f) => f > 0 && !f.isNaN && !f.isInfinite)
        .toList();

    if (validFreqs.isEmpty) return 0.0;

    // استخدام الوسيط لجميع المنصات (أكثر استقراراً)
    validFreqs.sort();
    if (validFreqs.length % 2 == 0) {
      return (validFreqs[validFreqs.length ~/ 2 - 1] +
              validFreqs[validFreqs.length ~/ 2]) /
          2;
    } else {
      return validFreqs[validFreqs.length ~/ 2];
    }
  }

  /// تحسين 14: تحديث التغذية الراجعة موحد
  void _updateFeedback() {
    if (_currentFrequency <= 0 || _detectedNote == '--') {
      _feedbackText = 'استمع...';
      _feedbackColor = Colors.orange;
      return;
    }

    final cents = _getCentsDifference();
    const double tolerance = 12.0; // تساهل موحد

    if (cents.abs() <= tolerance) {
      _feedbackText = '🎯 ممتاز!';
      _feedbackColor = Colors.green;
    } else if (cents > tolerance) {
      _feedbackText = '📉 عالي قليلاً';
      _feedbackColor = Colors.red;
    } else {
      _feedbackText = '📈 منخفض قليلاً';
      _feedbackColor = Colors.blue;
    }
  }

  /// تبديل حالة التسجيل (بدء/إيقاف)
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
    return Container(
      width: widget.width,
      height: widget.height,
      padding: EdgeInsets.all(12),
      child: Column(
        children: [
          // صف يحتوي على النغمة المكتشفة والبعد عن النغمة
          Expanded(
            flex: 3,
            child: Row(
              children: [
                // النغمة المكتشفة
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(12),
                    margin: EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 2,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'النغمة المكتشفة',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          _detectedNote,
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: _detectedNote != '--'
                                ? Colors.green[700]
                                : Colors.grey[400],
                          ),
                        ),
                        SizedBox(height: 2),
                        Text(
                          '${_currentFrequency.toStringAsFixed(2)} Hz',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (isWeb)
                          Text(
                            'وضع الويب',
                            style: TextStyle(
                              fontSize: 8,
                              color: Colors.blue[600],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),

                // البعد عن النغمة
                Expanded(
                  child: Container(
                    padding: EdgeInsets.all(12),
                    margin: EdgeInsets.only(left: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.2),
                          spreadRadius: 2,
                          blurRadius: 8,
                          offset: Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'البعد عن النغمة',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          '${_getCentsDifference().toStringAsFixed(0)} Cent',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color:
                                _getCentsDifference().abs() <= (isWeb ? 15 : 10)
                                ? Colors.green[700]
                                : Colors.red[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),

          SizedBox(height: 12),

          // التغذية الراجعة
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.2),
                    spreadRadius: 2,
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ],
              ),
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _feedbackText,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: _feedbackColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (isWeb && !_isInitialized && !_isInitializing)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text(
                          'للويب: اضغط "السماح" عند طلب إذن الميكروفون',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (isWeb && _isInitialized)
                      Padding(
                        padding: const EdgeInsets.only(top: 4.0),
                        child: Text(
                          'تم تحسين الخوارزمية للويب',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.green[600],
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),

          SizedBox(height: 12),

          // زر البدء/الإيقاف
          Expanded(
            flex: 2,
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isInitializing ? null : _toggleRecording,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _isRecording
                      ? Colors.red[600]
                      : (_isInitializing ? Colors.grey : Colors.green[600]),
                  foregroundColor: Colors.white,
                  elevation: 4,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  padding: EdgeInsets.zero,
                ),
                child: Text(
                  _isInitializing
                      ? 'جاري التحميل...'
                      : (_isRecording ? 'إيقاف التسجيل' : 'بدء التسجيل'),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    _analysisTimer?.cancel();
    _audioSubscription?.cancel();
    _audioRecorder.dispose();
    super.dispose();
  }
}

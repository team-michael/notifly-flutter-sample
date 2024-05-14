// ignore_for_file: library_private_types_in_public_api

import 'dart:io';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'firebase_options.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:rxdart/rxdart.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:notifly_flutter/notifly_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class MyNotifManager {
  static final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  // static final onNotifications = BehaviorSubject<RemoteMessage?>(); - Pub/Sub 패턴 클릭 핸들러 고도화

  static Future<void> init() async {
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('mipmap/ic_launcher');
    final DarwinInitializationSettings initializationSettingsIOS =
        DarwinInitializationSettings(
            // iOS 9 이하 버전에서 로컬 알림을 클릭했을 때 호출
            onDidReceiveLocalNotification: (id, title, body, payload) async {});
    final InitializationSettings initializationSettings =
        InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsIOS,
    );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
    );
  }

  // 알림 클릭 시 수행할 작업
  static void onDidReceiveNotificationResponse(
      NotificationResponse notificationResponse) async {
    final String payload = notificationResponse.payload ?? '';
    if (payload.isEmpty) {
      return;
    }
    final Map<String, dynamic> data = jsonDecode(payload);
    final RemoteMessage message = RemoteMessage.fromMap(data);
    await _handlePushNotificationClicked(message);
    // or onNotifications.add(message); - Pub/Sub 패턴으로 구현
  }

  static void _showLocalPushNotification(RemoteMessage message) async {
    await mayCreateAndroidNotificationChannel();
    final notification = message.notification;
    if (notification == null) {
      return;
    }
    const platformChannelSpecifics = NotificationDetails(
      android: AndroidNotificationDetails(
        'channel id',
        'channel name',
        channelDescription: 'channel description',
        importance: Importance.max,
        priority: Priority.high,
        icon: 'mipmap/ic_launcher',
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        badgeNumber: 1,
      ),
    );
    // 알림 표시
    await flutterLocalNotificationsPlugin.show(
        0, notification.title, notification.body, platformChannelSpecifics,
        payload: jsonEncode(message.toMap()));
  }

  static Future<void> mayCreateAndroidNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      'high_importance_channel', // 채널 ID
      'High Importance Notifications', // 채널 이름
      description: 'This channel is used for important notifications.', // 채널 설명
      importance: Importance.max, // 중요도 설정
    );

    // 알림 채널 생성
    final AndroidFlutterLocalNotificationsPlugin? androidPlugin =
        flutterLocalNotificationsPlugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin != null) {
      androidPlugin.createNotificationChannel(channel);
    }
  }
}

AndroidNotificationChannel channel = const AndroidNotificationChannel(
  'high_importance_channel', // id
  'High Importance Notifications', // title
  description:
      'This channel is used for important notifications.', // description
  importance: Importance.high,
);

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

void main() async {
  await dotenv.load(fileName: "assets/.env");

  WidgetsFlutterBinding.ensureInitialized();
  await NotiflyPlugin.initialize(
    projectId: dotenv.env['NOTIFLY_PROJECT_ID']!,
    username: dotenv.env['NOTIFLY_USERNAME']!,
    password: dotenv.env['NOTIFLY_PASSWORD']!,
  );
  await NotiflyPlugin.requestPermission();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // background messaging 수신 핸들링
  FirebaseMessaging.onBackgroundMessage(_handlePushNotificationReceived);
  // background messaging 클릭 핸들링
  FirebaseMessaging.onMessageOpenedApp.listen(_handlePushNotificationClicked);

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Notifly Flutter Sample',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _selectedIndex = 0;
  String _token = '';
  String _userId = '';
  String _notiflyEvent = '';
  bool _authorized = false;

  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _bodyController = TextEditingController();
  final TextEditingController _urlController = TextEditingController();
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  Future<void> _sendNotiflyEvent() async {
    await NotiflyPlugin.trackEvent(eventName: _notiflyEvent);
  }

  Future<void> _sendLocalPushNotification() async {
    const int notificationId = 0; // 고유한 알림 ID
    String? imagePath; // 로컬 이미지 경로

    // 선택한 이미지가 있다면 임시 파일로 저장 (이 예제에서는 생략)
    if (_selectedImage != null) {
      imagePath = _selectedImage!.path;
    }

    // 알림 세부 사항 설정
    AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      channel.id, // 알림 채널 ID
      channel.name, // 알림 채널 이름
      channelDescription: channel.description, // 채널 설명
      importance: Importance.max, // 최대 중요도
      priority: Priority.high, // 높은 우선순위
      icon: 'mipmap/ic_launcher', // 앱 아이콘
      largeIcon: imagePath != null
          ? FilePathAndroidBitmap(imagePath)
          : null, // 대형 아이콘 (이미지)
    );

    NotificationDetails platformChannelSpecifics = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(
        presentAlert: true, // 알림 표시
        presentBadge: true, // 배지 표시
        presentSound: true, // 사운드 재생
      ),
    );

    // 알림 표시
    await flutterLocalNotificationsPlugin.show(
      notificationId,
      _titleController.text, // 알림 제목
      _bodyController.text, // 알림 내용
      platformChannelSpecifics,
      payload: _pushAction == 'open_url' ? _urlController.text : null,
    );
  }

  void _navigateToItemDetail(String? payload) {
    // Navigator를 사용하여 앱 내에서 적절한 화면으로 이동
    // 예: Navigator.pushNamed(context, payload);

    // 혹은 딥링크 또는 URL 처리
    if (payload != null) {
      if (payload.startsWith('http://') || payload.startsWith('https://')) {
        // 외부 브라우저에서 URL 열기
        launchUrl(Uri.parse(payload));
      } else {
        // 딥링크 처리, 예: Flutter의 navigator를 사용하여 내부 페이지로 이동
        // Navigator.pushNamed(context, payload);
      }
    }
  }

  // Future<void> listenLocalNotifClickAction() async {
  //   // Subscribe to the stream of notifications
  //   MyNotifManager.onNotifications.listen((RemoteMessage? message) async {
  //     if (message != null) {
  //       await _handlePushNotificationClicked(message);
  //     }
  //   });
  // }

  Future<void> _initListeners() async {
    // Foreground 수신 메시지 처리
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Foreground 수신 메시지 알림 생성 - ONLY Android
      RemoteNotification? notification = message.notification;
      AndroidNotification? android = message.notification?.android;
      if (notification != null && android != null) {
        MyNotifManager._showLocalPushNotification(message);
      }

      _handlePushNotificationReceived(message); // 수신 핸들러 호출
    });

    // Foreground 수신 메시지 알림 생성 - ONLY iOS
    await _messaging.setForegroundNotificationPresentationOptions(
      alert: true, // Required to display a heads up notification
      badge: true,
      sound: true,
    );

    // 앱이 종료된 상태에서 메시지 클릭 시 수행할 작업 - handle cold start notification
    final initialMessage = await _messaging.getInitialMessage();
    if (initialMessage != null) {
      await _handlePushNotificationClicked(initialMessage);
    }
  }

  Future<void> _requestPermission() async {
    final permission = await _messaging.requestPermission();
    _authorized =
        permission.authorizationStatus == AuthorizationStatus.authorized;
    if (permission.authorizationStatus == AuthorizationStatus.denied) {
      print("[🔥Notifly] Permission denied.");
      return;
    }
    await _initListeners();
  }

  @override
  void initState() {
    super.initState();
    _requestPermission();
    _getToken();
    MyNotifManager.init();
    // listenLocalNotifClickAction(); // Pub/Sub 패턴 클릭 핸들러 고도화
  }

  Future<void> _getToken() async {
    String? token = await FirebaseMessaging.instance.getToken();
    setState(() {
      _token = token ?? '';
      if (_token.isNotEmpty) {
        // TODO: 서버에 토큰 전송
      }
    });
  }

  void _setUserId() {
    // Notifly SDK를 사용하여 사용자 ID 설정
    NotiflyPlugin.setUserId(_userId);
    print('User ID: $_userId');
  }

  File? _selectedImage;
  String _pushAction = 'open_app';
  String _actionUrl = '';

  Future<void> _selectImage() async {
    final picker = ImagePicker();
    final pickedImage = await picker.pickImage(source: ImageSource.gallery);
    if (pickedImage != null) {
      setState(() {
        _selectedImage = File(pickedImage.path);
      });
    }
  }

  String? _validateActionUrl() {
    if (_pushAction == 'deeplink' && !_actionUrl.contains('://')) {
      return '유효한 딥링크 스키마를 입력해주세요.';
    } else if (_pushAction == 'open_url' &&
        !_actionUrl.startsWith('https://')) {
      return 'URL은 "https://"로 시작해야 합니다.';
    }
    return null;
  }

  bool _isButtonDisabled() {
    if (_titleController.text.isEmpty || _bodyController.text.isEmpty) {
      return true;
    }
    if ((_pushAction == 'deeplink' || _pushAction == 'open_url') &&
        _validateActionUrl() != null) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifly Flutter Sample'),
      ),
      body: _selectedIndex == 0 ? _buildNotiflyTab() : _buildFCMTab(),
      bottomNavigationBar: BottomNavigationBar(
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications),
            label: 'Notifly',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_active),
            label: 'FCM',
          ),
        ],
        currentIndex: _selectedIndex,
        onTap: (index) {
          setState(() {
            _selectedIndex = index;
          });
        },
      ),
    );
  }

  Widget _buildNotiflyTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset('assets/notifly_logo.png'),
            const SizedBox(height: 16.0),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    onChanged: (value) {
                      setState(() {
                        _userId = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: 'User ID',
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  flex: 1,
                  child: ElevatedButton(
                    onPressed: _setUserId,
                    child: const Text('설정'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            TextField(
              readOnly: true,
              controller: TextEditingController(text: _token),
              decoration: InputDecoration(
                labelText: 'Token',
                suffixIcon: IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _token));
                    // ScaffoldMessenger.of(context).showSnackBar(
                    //   const SnackBar(
                    //     content: Text('토큰이 복사되었습니다.'),
                    //     duration: Duration(seconds: 2),
                    //   ),
                    // );
                  },
                  icon: const Icon(Icons.copy),
                ),
              ),
            ),
            const SizedBox(height: 16.0),
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    onChanged: (value) {
                      setState(() {
                        _notiflyEvent = value;
                      });
                    },
                    decoration: const InputDecoration(
                      labelText: '이벤트 이름',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: _sendNotiflyEvent,
              child: const Text('노티플라이 푸시 테스트'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFCMTab() {
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Image.asset('assets/notifly_logo.png'),
            const SizedBox(height: 16.0),
            TextField(
              readOnly: true,
              controller: TextEditingController(text: _token),
              decoration: InputDecoration(
                labelText: 'Token',
                suffixIcon: IconButton(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _token));
                  },
                  icon: const Icon(Icons.copy),
                ),
              ),
            ),
            const SizedBox(height: 16.0),
            TextField(
              controller: _titleController,
              onChanged: (value) {
                setState(() {});
              },
              decoration: InputDecoration(
                labelText: 'Title',
                errorText: _titleController.text.isEmpty ? '제목을 입력해주세요.' : null,
              ),
            ),
            const SizedBox(height: 16.0),
            TextField(
              controller: _bodyController,
              onChanged: (value) {
                setState(() {});
              },
              decoration: InputDecoration(
                labelText: 'Body',
                errorText: _bodyController.text.isEmpty ? '내용을 입력해주세요.' : null,
              ),
            ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed: _selectImage,
              child: const Text('이미지 업로드'),
            ),
            if (_selectedImage != null)
              Image.file(
                _selectedImage!,
                height: 200,
                fit: BoxFit.cover,
              ),
            const SizedBox(height: 16.0),
            const Text('앱 푸시 액션 설정'),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 16.0,
              children: [
                ChoiceChip(
                  label: const Text('앱 열기'),
                  selected: _pushAction == 'open_app',
                  onSelected: (selected) {
                    setState(() {
                      _pushAction = 'open_app';
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('딥링크'),
                  selected: _pushAction == 'deeplink',
                  onSelected: (selected) {
                    setState(() {
                      _pushAction = 'deeplink';
                    });
                  },
                ),
                ChoiceChip(
                  label: const Text('URL 열기'),
                  selected: _pushAction == 'open_url',
                  onSelected: (selected) {
                    setState(() {
                      _pushAction = 'open_url';
                    });
                  },
                ),
              ],
            ),
            if (_pushAction == 'open_url' || _pushAction == 'deeplink')
              Padding(
                padding: const EdgeInsets.only(top: 16.0),
                child: TextField(
                  controller: _urlController,
                  onChanged: (value) {
                    setState(() {
                      _actionUrl = value;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: 'URL',
                    errorText: _validateActionUrl(),
                  ),
                ),
              ),
            const SizedBox(height: 16.0),
            ElevatedButton(
              onPressed:
                  _isButtonDisabled() ? null : _sendLocalPushNotification,
              child: const Text('FCM 푸시 테스트'),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _handlePushNotificationClicked(RemoteMessage message) async {
  print("[🔥Notifly] Push Notification Clicked!");
  final Map<String, dynamic>? notification = message.notification?.toMap();
  final Map<String, dynamic> data = message.data;
  print("[🔥Notifly] notification: $notification");
  print("[🔥Notifly] data: $data");

  /* 
    TODO: 알림 클릭 시 수행할 작업을 추가하세요.
    1. 딥링크 또는 URL 처리
    2. 푸시 알림 클릭 이벤트 로깅
  */
}

Future<void> _handlePushNotificationReceived(RemoteMessage message) async {
  print("[🔥Notifly] Push Notification Received!");
  final Map<String, dynamic>? notification = message.notification?.toMap();
  final Map<String, dynamic> data = message.data;
  print("[🔥Notifly] notification: $notification");
  print("[🔥Notifly] data: $data");
  /* 
    TODO: 알림 수신 시 수행할 작업을 추가하세요.
    1. 알림을 기기에 저장 (추후 알림함 구현시 사용)
    2. 푸시 알림 수신 이벤트 로깅
  */
}

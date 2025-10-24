import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('ko_KR', null);
  runApp(const UlsanCalendarApp());
}

class UlsanCalendarApp extends StatelessWidget {
  const UlsanCalendarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '울산캘린더',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const MainPage(),
    );
  }
}

// ----------------------------------------------------------------------------
// 메인 페이지 (하단 네비게이션)
// ----------------------------------------------------------------------------
class MainPage extends StatefulWidget {
  const MainPage({super.key});
  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  final List<Widget> _pages = [
    const CalendarPage(),
    const NewsPage(),
    const BoardPage(),
    const MapPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.calendar_month), label: '캘린더'),
          NavigationDestination(icon: Icon(Icons.article), label: '뉴스'),
          NavigationDestination(icon: Icon(Icons.forum), label: '자유게시판'),
          NavigationDestination(icon: Icon(Icons.map), label: '지도'),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// ① 캘린더 (일정 추가 가능)
// ----------------------------------------------------------------------------
class CalendarPage extends StatefulWidget {
  const CalendarPage({super.key});
  @override
  State<CalendarPage> createState() => _CalendarPageState();
}

class _CalendarPageState extends State<CalendarPage> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<String, List<String>> _events = {};

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<void> _loadEvents() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('events');
    if (saved != null) {
      setState(() {
        _events = Map<String, List<String>>.from(json.decode(saved));
      });
    }
  }

  Future<void> _saveEvents() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('events', json.encode(_events));
  }

  List<String> _getEventsForDay(DateTime day) {
    final key = "${day.year}-${day.month}-${day.day}";
    return _events[key] ?? [];
  }

  void _addEvent(DateTime date, String event) {
    final key = "${date.year}-${date.month}-${date.day}";
    setState(() {
      if (_events[key] == null) _events[key] = [];
      _events[key]!.add(event);
    });
    _saveEvents();
  }

  void _showAddEventDialog(DateTime selected) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text("${selected.month}월 ${selected.day}일 일정 추가"),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(hintText: "일정 내용 입력"),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                _addEvent(selected, controller.text.trim());
              }
              Navigator.pop(context);
            },
            child: const Text("추가"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("📅 울산캘린더")),
      body: Column(
        children: [
          TableCalendar(
            locale: 'ko_KR',
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (d) => isSameDay(_selectedDay, d),
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = selected;
                _focusedDay = focused;
              });
              showModalBottomSheet(
                context: context,
                builder: (_) => _eventList(selected),
              );
            },
            eventLoader: _getEventsForDay,
            calendarStyle: const CalendarStyle(
              todayDecoration: BoxDecoration(color: Colors.blue, shape: BoxShape.circle),
              selectedDecoration: BoxDecoration(color: Colors.orange, shape: BoxShape.circle),
            ),
          ),
        ],
      ),
      floatingActionButton: _selectedDay == null
          ? null
          : FloatingActionButton(
        onPressed: () => _showAddEventDialog(_selectedDay!),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _eventList(DateTime day) {
    final events = _getEventsForDay(day);
    return SizedBox(
      height: 300,
      child: Column(
        children: [
          ListTile(
            title: Text("${day.month}월 ${day.day}일 일정 (${events.length}개)"),
            trailing: IconButton(
              icon: const Icon(Icons.add),
              onPressed: () {
                Navigator.pop(context);
                _showAddEventDialog(day);
              },
            ),
          ),
          Expanded(
            child: events.isEmpty
                ? const Center(child: Text("등록된 일정이 없습니다."))
                : ListView.builder(
              itemCount: events.length,
              itemBuilder: (context, i) => ListTile(
                leading: const Icon(Icons.event),
                title: Text(events[i]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// ② 뉴스 페이지 (AI 뉴스 자동 수집)
// ----------------------------------------------------------------------------
class NewsPage extends StatefulWidget {
  const NewsPage({super.key});
  @override
  State<NewsPage> createState() => _NewsPageState();
}

class _NewsPageState extends State<NewsPage> {
  List articles = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    fetchNews();
  }

  Future<void> fetchNews() async {
    const apiUrl =
        'https://newsapi.org/v2/everything?q=울산 문화 OR 울산 축제&language=ko&sortBy=publishedAt&apiKey=2b208ebd795b4f0fb9e380844f894932';
    final res = await http.get(Uri.parse(apiUrl));
    if (res.statusCode == 200) {
      setState(() {
        articles = json.decode(res.body)['articles'];
        loading = false;
      });
    } else {
      setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("📰 울산 문화 뉴스")),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: articles.length,
        itemBuilder: (context, i) {
          final a = articles[i];
          return Card(
            margin: const EdgeInsets.all(8),
            child: ListTile(
              leading: a['urlToImage'] != null
                  ? Image.network(a['urlToImage'], width: 80, fit: BoxFit.cover)
                  : const Icon(Icons.article),
              title: Text(a['title'] ?? ''),
              subtitle: Text(a['description'] ?? ''),
              onTap: () {
                showDialog(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(a['title'] ?? ''),
                    content: Text(a['content'] ?? '내용 없음'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text("닫기")),
                    ],
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// ③ 자유게시판 (앱 종료 후에도 글 유지)
// ----------------------------------------------------------------------------
class BoardPage extends StatefulWidget {
  const BoardPage({super.key});
  @override
  State<BoardPage> createState() => _BoardPageState();
}

class _BoardPageState extends State<BoardPage> {
  final controller = TextEditingController();
  List<String> posts = [];

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList('posts') ?? [];
    setState(() => posts = saved);
  }

  Future<void> _savePosts() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setStringList('posts', posts);
  }

  void _addPost() {
    if (controller.text.trim().isEmpty) return;
    setState(() {
      posts.insert(0, controller.text.trim());
    });
    controller.clear();
    _savePosts();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("💬 자유게시판")),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    decoration: const InputDecoration(
                        hintText: "글을 입력하세요", border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(onPressed: _addPost, child: const Text("등록")),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: posts.length,
              itemBuilder: (context, i) => Card(
                margin: const EdgeInsets.all(6),
                child: ListTile(title: Text(posts[i])),
              ),
            ),
          )
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------------
// ④ 지도 (내 위치 빨간 점 표시)
// ----------------------------------------------------------------------------
class MapPage extends StatefulWidget {
  const MapPage({super.key});
  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  GoogleMapController? mapController;
  LatLng? currentPos;

  final List<Marker> _markers = [
    const Marker(
      markerId: MarkerId('태화강'),
      position: LatLng(35.5395, 129.3116),
      infoWindow: InfoWindow(title: '태화강 국가정원'),
    ),
    const Marker(
      markerId: MarkerId('고래문화마을'),
      position: LatLng(35.498, 129.364),
      infoWindow: InfoWindow(title: '장생포 고래문화마을'),
    ),
    const Marker(
      markerId: MarkerId('간절곶'),
      position: LatLng(35.3573, 129.3603),
      infoWindow: InfoWindow(title: '간절곶 해맞이 명소'),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _determinePosition();
  }

  Future<void> _determinePosition() async {
    LocationPermission permission = await Geolocator.requestPermission();
    Position pos = await Geolocator.getCurrentPosition();
    setState(() {
      currentPos = LatLng(pos.latitude, pos.longitude);
      _markers.add(
        Marker(
          markerId: const MarkerId('현재위치'),
          position: currentPos!,
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
          infoWindow: const InfoWindow(title: '내 위치'),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("🗺 지도")),
      body: currentPos == null
          ? const Center(child: CircularProgressIndicator())
          : GoogleMap(
        initialCameraPosition:
        CameraPosition(target: currentPos!, zoom: 12),
        markers: Set.from(_markers),
        myLocationEnabled: true,
        onMapCreated: (controller) => mapController = controller,
      ),
    );
  }
}

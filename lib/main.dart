import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest.dart' as tz_data;


const appName = 'ZAG Nyimbo za Chitsitsimutso';
const brandTitle = 'Zomba Assemblies Hymns';
const appTagline = 'Nyimbo za Chitsitsimutso';
const appVersion = '1.7';
const logoAsset = 'adds/logo.png';
const databaseAsset = 'adds/chitsitsimutso.db';
const _themeModeKey = 'night_mode_enabled';
const _readingLangKey = 'reading_language'; // 'chichewa' | 'english'
const _fontSizeKey = 'global_font_size';

// Global font-size scale (0.85 – 1.30), notifies listeners
final fontSizeNotifier = ValueNotifier<double>(1.0);

Future<void> _loadFontSize() async {
  final prefs = await SharedPreferences.getInstance();
  fontSizeNotifier.value = (prefs.getDouble(_fontSizeKey) ?? 1.0).clamp(0.85, 1.30);
}

Future<void> _saveFontSize(double v) async {
  fontSizeNotifier.value = v;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble(_fontSizeKey, v);
}

// Reading language notifier
final readingLangNotifier = ValueNotifier<String>('chichewa');

Future<void> _loadReadingLang() async {
  final prefs = await SharedPreferences.getInstance();
  readingLangNotifier.value = prefs.getString(_readingLangKey) ?? 'chichewa';
}

Future<void> _saveReadingLang(String lang) async {
  readingLangNotifier.value = lang;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_readingLangKey, lang);
}

const _navy = Color(0xFF1A3A8F);
const _gold = Color(0xFFC89A3C);
const _ink = Color(0xFF1A2340);
const _muted = Color(0xFF6B7A99);
const _paper = Color(0xFFF4F6FB);
const _mist = Color(0xFFE8EDF7);
const _green = Color(0xFF1565C0);
const _rose = Color(0xFF8E3155);
const _line = Color(0x1A1A3A8F);
const _night = Color(0xFF0D1117);
const _nightMist = Color(0xFF131929);
const _nightSurface = Color(0xFF1C2438);
const _nightText = Color(0xFFEEF2FF);
const _nightMuted = Color(0xFFB0BCDA);
const _nightLine = Color(0x33FFFFFF);

final appTheme = AppThemeController();
final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Future.wait([appTheme.load(), _loadFontSize(), _loadReadingLang()]);
  await _initNotifications();
  runApp(const ZombaHymnsApp());
}

Future<void> _initNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  );
  const initSettings = InitializationSettings(android: androidSettings, iOS: iosSettings);
  await _notificationsPlugin.initialize(initSettings);

  // Create notification channel for Android
  const androidChannel = AndroidNotificationChannel(
    'bible_reading_reminders',
    'Bible Reading Reminders',
    description: 'Daily reminders to read the ZAG Bible reading plan',
    importance: Importance.high,
  );
  await _notificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(androidChannel);

  // Request permissions (Android 13+)
  await _notificationsPlugin
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.requestNotificationsPermission();

  // Schedule daily reminders
  await _scheduleDailyReminders();
}

Future<void> _scheduleDailyReminders() async {
  tz_data.initializeTimeZones();
  final now = tz.TZDateTime.now(tz.local);
  final todaysVerse = await fetchTodaysVerse();
  final verseText = todaysVerse?.text ?? 'Read your daily Bible verse';
  final shortText = verseText.length > 100 ? '${verseText.substring(0, 100)}...' : verseText;

  const androidDetails = AndroidNotificationDetails(
    'bible_reading_reminders',
    'Bible Reading Reminders',
    channelDescription: 'Daily reminders to read the ZAG Bible reading plan',
    importance: Importance.high,
    priority: Priority.high,
    styleInformation: BigTextStyleInformation(''),
  );
  const iosDetails = DarwinNotificationDetails();
  const notificationDetails = NotificationDetails(android: androidDetails, iOS: iosDetails);

  // Schedule 3 reminders per day
  final times = [
    tz.TZDateTime(tz.local, now.year, now.month, now.day, 8, 0),   // 8:00 AM
    tz.TZDateTime(tz.local, now.year, now.month, now.day, 14, 0),  // 2:00 PM
    tz.TZDateTime(tz.local, now.year, now.month, now.day, 20, 0),  // 8:00 PM
  ];

  for (var i = 0; i < times.length; i++) {
    final scheduledTime = times[i];
    await _notificationsPlugin.zonedSchedule(
      i,
      'ZOMBA ASSEMBLIES BIBLE READING REMINDER',
      shortText,
      scheduledTime,
      notificationDetails,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }
}

class ZombaHymnsApp extends StatelessWidget {
  const ZombaHymnsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: appTheme,
      builder: (context, _) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: appName,
          theme: _buildAppTheme(Brightness.light),
          darkTheme: _buildAppTheme(Brightness.dark),
          themeMode: appTheme.mode,
          home: const SplashScreen(),
        );
      },
    );
  }
}

ThemeData _buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: _navy,
    primary: dark ? _gold : _navy,
    secondary: _gold,
    brightness: brightness,
  );
  final foreground = dark ? _nightText : _ink;
  final background = dark ? _night : _paper;
  final surface = dark ? _nightSurface : Colors.white;
  final divider = dark ? _nightLine : _line;

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    dividerColor: divider,
    textTheme: (dark ? ThemeData.dark() : ThemeData.light()).textTheme.apply(
      bodyColor: foreground,
      displayColor: foreground,
    ),
    appBarTheme: AppBarTheme(
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      backgroundColor: Colors.transparent,
      foregroundColor: foreground,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? _nightSurface : _paper,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: WidgetStateProperty.all(0),
      backgroundColor: WidgetStateProperty.all(surface.withValues(alpha: 0.96)),
      side: WidgetStateProperty.all(BorderSide(color: divider)),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    ),
  );
}

class AppThemeController extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  bool get isDark => _mode == ThemeMode.dark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = (prefs.getBool(_themeModeKey) ?? false)
        ? ThemeMode.dark
        : ThemeMode.light;
  }

  Future<void> toggle() async {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_themeModeKey, isDark);
  }
}

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _surfaceColor(BuildContext context, {double alpha = 1}) {
  final color = _isDark(context) ? _nightSurface : Colors.white;
  return color.withValues(alpha: alpha);
}

Color _textColor(BuildContext context) => _isDark(context) ? _nightText : _ink;

Color _mutedColor(BuildContext context) =>
    _isDark(context) ? _nightMuted : _muted;

Color _lineColor(BuildContext context) => _isDark(context) ? _nightLine : _line;

enum HymnCollection {
  chichewa(
    tableName: 'chichewa',
    label: 'Chichewa',
    subtitle: 'Nyimbo za Chitsitsimutso',
    description: 'Chichewa revival hymns',
    icon: Icons.menu_book_rounded,
    color: _navy,
  ),
  tumbuka(
    tableName: 'chitumbuka',
    label: 'Chitumbuka',
    subtitle: 'Sumu za chitsitsimutso',
    description: 'Tumbuka hymn collection',
    icon: Icons.library_music_rounded,
    color: Color(0xFF1976D2),
  ),
  favourites(
    tableName: '',
    label: 'Favourites',
    subtitle: 'Saved hymns',
    description: 'Marked hymns',
    icon: Icons.favorite_rounded,
    color: _rose,
  ),
  english(
    tableName: '',
    label: 'English',
    subtitle: 'English Hymns',
    description: 'English hymn collection',
    icon: Icons.music_note_rounded,
    color: Color(0xFF6A1B9A),
  );

  const HymnCollection({
    required this.tableName,
    required this.label,
    required this.subtitle,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String tableName;
  final String label;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color color;

  static Iterable<HymnCollection> get databaseCollections => const [
    HymnCollection.chichewa,
    HymnCollection.tumbuka,
  ];

  bool get isComingSoon =>
      this == HymnCollection.english;
}

class Hymn {
  const Hymn({
    required this.id,
    required this.collection,
    required this.number,
    required this.title,
    required this.lyrics,
    required this.chord,
  });

  final String id;
  final HymnCollection collection;
  final String number;
  final String title;
  final String lyrics;
  final String? chord;

  String get searchable => _searchText('$number $title $lyrics ${chord ?? ''}');

  String get searchableTitle => _searchText('$number $title');
}

String _searchText(String value) {
  return value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

List<String> _searchTokens(String value) {
  return _searchText(
    value,
  ).split(' ').where((token) => token.isNotEmpty).toList();
}

int _hymnNumberSort(String left, String right) {
  final leftNumber = int.tryParse(left);
  final rightNumber = int.tryParse(right);

  if (leftNumber != null && rightNumber != null) {
    return leftNumber.compareTo(rightNumber);
  }

  return left.compareTo(right);
}

class HymnSearchMatch {
  const HymnSearchMatch(this.hymn, this.score);

  final Hymn hymn;
  final int score;
}

class HymnRepository {
  Database? _database;
  List<Hymn>? _allHymns;

  Future<List<Hymn>> hymnsFor(HymnCollection collection) async {
    final hymns = await loadAllHymns();

    if (collection == HymnCollection.favourites) {
      final favouriteIds = await FavouriteStore.instance.ids();
      return hymns.where((hymn) => favouriteIds.contains(hymn.id)).toList();
    }

    return hymns.where((hymn) => hymn.collection == collection).toList();
  }

  Future<Map<HymnCollection, int>> collectionCounts() async {
    final hymns = await loadAllHymns();
    final favouriteIds = await FavouriteStore.instance.ids();

    return {
      for (final collection in HymnCollection.databaseCollections)
        collection: hymns.where((hymn) => hymn.collection == collection).length,
      HymnCollection.favourites: hymns
          .where((hymn) => favouriteIds.contains(hymn.id))
          .length,
    };
  }

  Future<List<Hymn>> loadAllHymns() async {
    if (_allHymns != null) {
      return _allHymns!;
    }

    final db = await _openDatabase();
    final tableNames = await _tableNames(db);
    final hymns = <Hymn>[];

    for (final collection in HymnCollection.databaseCollections) {
      final actualTable = tableNames[collection.tableName.toLowerCase()];
      if (actualTable == null) {
        throw HymnDatabaseException(
          'The bundled database is missing the "${collection.tableName}" table.',
        );
      }

      final columns = await _columnNames(db, actualTable);
      final id = _column(columns, 'ID', mustExist: true)!;
      final number = _column(columns, 'SONGNUMBER', mustExist: true)!;
      final title = _column(columns, 'TITLE', mustExist: true)!;
      final lyricColumns = _lyricColumns(columns);
      final chord = _column(columns, 'CHORD');

      final rows = await db.query(
        actualTable,
        orderBy:
            '''
          CAST(${_q(number)} AS INTEGER) ASC,
          ${_q(number)} COLLATE NOCASE ASC,
          ${_q(title)} COLLATE NOCASE ASC
        ''',
      );

      hymns.addAll(
        rows.map(
          (row) => _mapHymn(
            collection,
            row,
            idColumn: id,
            numberColumn: number,
            titleColumn: title,
            lyricColumns: lyricColumns,
            chordColumn: chord,
          ),
        ),
      );
    }

    _allHymns = hymns;
    return hymns;
  }

  Hymn _mapHymn(
    HymnCollection collection,
    Map<String, Object?> row, {
    required String idColumn,
    required String numberColumn,
    required String titleColumn,
    required List<String> lyricColumns,
    required String? chordColumn,
  }) {
    final id =
        _cleanText(row[idColumn]) ?? '${collection.tableName}-${row.hashCode}';
    final number = _cleanText(row[numberColumn]) ?? id;
    final title = _cleanText(row[titleColumn]) ?? 'Hymn $number';
    final body = _combinedLyrics(row, lyricColumns);
    final chord = chordColumn == null ? null : _cleanText(row[chordColumn]);

    return Hymn(
      id: '${collection.tableName}:$id',
      collection: collection,
      number: number,
      title: title,
      lyrics: body.isEmpty ? title : body,
      chord: chord,
    );
  }

  List<String> _lyricColumns(Map<String, String> columns) {
    final matches = columns.values.where((column) {
      final lower = column.toLowerCase();
      return lower == 'body' ||
          lower == 'lyric' ||
          lower == 'lyrics' ||
          lower.startsWith('verse') ||
          lower.startsWith('stanza') ||
          lower.startsWith('chorus') ||
          lower.startsWith('refrain');
    }).toList();

    matches.sort((left, right) {
      final bodyCompare = _bodyColumnRank(
        left,
      ).compareTo(_bodyColumnRank(right));
      if (bodyCompare != 0) {
        return bodyCompare;
      }
      final leftNumber = _columnNumber(left);
      final rightNumber = _columnNumber(right);
      if (leftNumber != null && rightNumber != null) {
        return leftNumber.compareTo(rightNumber);
      }
      return left.toLowerCase().compareTo(right.toLowerCase());
    });

    return matches;
  }

  int _bodyColumnRank(String column) {
    final lower = column.toLowerCase();
    if (lower == 'body' || lower == 'lyrics' || lower == 'lyric') {
      return 0;
    }
    if (lower.startsWith('verse') || lower.startsWith('stanza')) {
      return 1;
    }
    return 2;
  }

  int? _columnNumber(String column) {
    final match = RegExp(r'\d+').firstMatch(column);
    return match == null ? null : int.tryParse(match.group(0)!);
  }

  String _combinedLyrics(Map<String, Object?> row, List<String> columns) {
    final seen = <String>{};
    final values = <String>[];

    for (final column in columns) {
      final value = _rawLyrics(row[column]);
      if (value != null && seen.add(value)) {
        values.add(value);
      }
    }

    final parts = values.where((value) {
      return !values.any(
        (other) =>
            other != value &&
            other.length > value.length &&
            other.contains(value),
      );
    }).toList();

    return parts.join('\n\n');
  }

  Future<Map<String, String>> _tableNames(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table'",
    );
    final values = <String, String>{};

    for (final row in rows) {
      final name = _cleanText(row['name']);
      if (name != null) {
        values[name.toLowerCase()] = name;
      }
    }

    return values;
  }

  Future<Map<String, String>> _columnNames(
    Database db,
    String tableName,
  ) async {
    final rows = await db.rawQuery('PRAGMA table_info(${_q(tableName)})');
    final values = <String, String>{};

    for (final row in rows) {
      final name = _cleanText(row['name']);
      if (name != null) {
        values[name.toLowerCase()] = name;
      }
    }

    if (values.isEmpty) {
      throw HymnDatabaseException(
        'Could not read the column list for "$tableName".',
      );
    }

    return values;
  }

  String? _column(
    Map<String, String> columns,
    String name, {
    bool mustExist = false,
  }) {
    final value = columns[name.toLowerCase()];
    if (value == null && mustExist) {
      throw HymnDatabaseException(
        'The bundled database is missing the "$name" column.',
      );
    }
    return value;
  }

  String _q(String identifier) {
    return '"${identifier.replaceAll('"', '""')}"';
  }

  // Preserves HTML tags so the UI parser can distinguish <p> vs <em> blocks.
  String? _rawLyrics(Object? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty || raw.toLowerCase() == 'null') return null;
    return raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').trim();
  }

  String? _cleanText(Object? value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty || raw.toLowerCase() == 'null') {
      return null;
    }

    return raw
        .replaceAll(r'\n', '\n')
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p\s*>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  Future<Database> _openDatabase() async {
    if (_database != null) {
      return _database!;
    }

    try {
      final dbDirectory = await getDatabasesPath();
      final dbPath = p.join(dbDirectory, 'zomba_chitsitsimutso.db');

      // Always refresh from the bundled asset so old installs do not keep stale
      // or partially copied databases.
      final data = await rootBundle.load(databaseAsset);
      final bytes = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      await databaseFactory.writeDatabaseBytes(dbPath, bytes);

      _database = await openDatabase(dbPath, readOnly: true);
      return _database!;
    } on MissingPluginException catch (_) {
      throw const HymnDatabaseException(
        'SQLite is not available on this platform with the current packages.',
      );
    } on StateError catch (error) {
      throw HymnDatabaseException(error.message);
    }
  }
}

class HymnDatabaseException implements Exception {
  const HymnDatabaseException(this.message);

  final String message;

  @override
  String toString() => message;
}

class FavouriteStore {
  FavouriteStore._();

  static final FavouriteStore instance = FavouriteStore._();
  static const _key = 'favourite_hymn_ids';

  Future<Set<String>> ids() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_key) ?? <String>[]).toSet();
  }

  Future<void> toggle(String id) async {
    final prefs = await SharedPreferences.getInstance();
    final values = (prefs.getStringList(_key) ?? <String>[]).toSet();
    if (!values.add(id)) {
      values.remove(id);
    }
    await prefs.setStringList(_key, values.toList()..sort());
  }
}

final hymnRepository = HymnRepository();

// Credits shown one at a time after the logo sequence
const _splashCredits = [
  _Credit(role: 'Senior Pastor', name: 'Rev Symon Msisya', icon: Icons.church_rounded),
  _Credit(role: 'Lead Developer', name: 'Leonard JJ Mhone', icon: Icons.code_rounded),
  _Credit(role: 'Presented by', name: 'ZAG Media Team', icon: Icons.groups_rounded),
  _Credit(role: 'Zomba Assemblies of God', name: 'Nyimbo za Chitsitsimutso', icon: Icons.music_note_rounded),
];

class _Credit {
  const _Credit({required this.role, required this.name, required this.icon});
  final String role;
  final String name;
  final IconData icon;
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  // Phase 1: logo + title animation (0–3 s)
  late final AnimationController _introCtrl;
  // Phase 2: credits cycling
  late final AnimationController _creditCtrl;
  int _creditIndex = 0;
  Timer? _creditTimer;
  Timer? _navTimer;

  // Total splash = intro (3 s) + credits (4 × 1.1 s) + exit gap = ~7.5 s
  static const _creditDuration = Duration(milliseconds: 1100);
  static const _introDuration  = Duration(milliseconds: 3000);
  static const _navDelay       = Duration(milliseconds: 7600);

  @override
  void initState() {
    super.initState();

    _introCtrl = AnimationController(vsync: this, duration: _introDuration)
      ..forward();

    _creditCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    // Start cycling credits after intro finishes
    Timer(const Duration(milliseconds: 3200), _startCredits);

    _navTimer = Timer(_navDelay, () {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          PageRouteBuilder<void>(
            transitionDuration: const Duration(milliseconds: 600),
            pageBuilder: (_, __, ___) => const HomeScreen(),
            transitionsBuilder: (_, anim, __, child) =>
                FadeTransition(opacity: anim, child: child),
          ),
        );
      }
    });
  }

  void _startCredits() {
    if (!mounted) return;
    _creditCtrl.forward(from: 0);
    _creditTimer = Timer.periodic(_creditDuration, (t) {
      if (!mounted) { t.cancel(); return; }
      final next = _creditIndex + 1;
      if (next >= _splashCredits.length) { t.cancel(); return; }
      _creditCtrl.reverse().then((_) {
        if (!mounted) return;
        setState(() => _creditIndex = next);
        _creditCtrl.forward(from: 0);
      });
    });
  }

  @override
  void dispose() {
    _creditTimer?.cancel();
    _navTimer?.cancel();
    _introCtrl.dispose();
    _creditCtrl.dispose();
    super.dispose();
  }

  CurvedAnimation _curve(AnimationController ctrl, double from, double to,
      [Curve curve = Curves.easeOutCubic]) =>
      CurvedAnimation(parent: ctrl, curve: Interval(from, to, curve: curve));

  @override
  Widget build(BuildContext context) {
    final bgReveal   = _curve(_introCtrl, 0.00, 0.35);
    final logoScale  = _curve(_introCtrl, 0.10, 0.55, Curves.elasticOut);
    final logoFade   = _curve(_introCtrl, 0.10, 0.40);
    final barGrow    = _curve(_introCtrl, 0.30, 0.65);
    final titleSlide = _curve(_introCtrl, 0.38, 0.68);
    final tagSlide   = _curve(_introCtrl, 0.48, 0.72);
    final shimmer    = _curve(_introCtrl, 0.60, 1.00, Curves.easeInOut);

    final credit = _splashCredits[_creditIndex];

    return Scaffold(
      body: AnimatedBuilder(
        animation: Listenable.merge([_introCtrl, _creditCtrl]),
        builder: (context, _) {
          return Stack(
            fit: StackFit.expand,
            children: [
              Opacity(
                opacity: bgReveal.value,
                child: const PremiumBackground(child: SizedBox.expand()),
              ),

              // Radial glow
              Center(
                child: Opacity(
                  opacity: (logoFade.value * 0.5).clamp(0.0, 0.5),
                  child: Container(
                    width: 260, height: 260,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        _gold.withValues(alpha: 0.28),
                        _navy.withValues(alpha: 0.0),
                      ]),
                    ),
                  ),
                ),
              ),

              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Logo
                    FadeTransition(
                      opacity: logoFade,
                      child: ScaleTransition(
                        scale: Tween<double>(begin: 0.0, end: 1.0).animate(logoScale),
                        child: const LogoMark(size: 110),
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Title
                    SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.6), end: Offset.zero,
                      ).animate(titleSlide),
                      child: FadeTransition(
                        opacity: titleSlide,
                        child: Text(
                          brandTitle,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w900, letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Tagline
                    SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, 0.8), end: Offset.zero,
                      ).animate(tagSlide),
                      child: FadeTransition(
                        opacity: tagSlide,
                        child: Text(
                          appTagline,
                          style: TextStyle(
                            color: _mutedColor(context),
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),

                    // Progress bar
                    FadeTransition(
                      opacity: barGrow,
                      child: Container(
                        width: 200, height: 5,
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        alignment: Alignment.centerLeft,
                        child: Stack(
                          children: [
                            FractionallySizedBox(
                              widthFactor: barGrow.value.clamp(0.0, 1.0),
                              child: Container(
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(colors: [_gold, _green]),
                                ),
                              ),
                            ),
                            if (shimmer.value > 0)
                              Positioned.fill(
                                child: FractionallySizedBox(
                                  alignment: Alignment.centerLeft,
                                  widthFactor: shimmer.value,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: [
                                        Colors.white.withValues(alpha: 0.0),
                                        Colors.white.withValues(alpha: 0.45),
                                        Colors.white.withValues(alpha: 0.0),
                                      ], stops: const [0.0, 0.5, 1.0]),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 36),

                    // ── Credits card ──────────────────────────────────
                    FadeTransition(
                      opacity: _creditCtrl,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, 0.3), end: Offset.zero,
                        ).animate(CurvedAnimation(
                          parent: _creditCtrl, curve: Curves.easeOutCubic,
                        )),
                        child: Container(
                          width: 260,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                          decoration: BoxDecoration(
                            color: _navy.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: _gold.withValues(alpha: 0.30)),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40, height: 40,
                                decoration: BoxDecoration(
                                  color: _gold.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Icon(credit.icon, color: _gold, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      credit.role,
                                      style: TextStyle(
                                        color: _gold.withValues(alpha: 0.85),
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        letterSpacing: 0.8,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      credit.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 20),

                    // Dot indicators
                    FadeTransition(
                      opacity: barGrow,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(_splashCredits.length, (i) {
                          final active = i == _creditIndex;
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: active ? 18 : 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: active
                                  ? _gold
                                  : _gold.withValues(alpha: 0.30),
                              borderRadius: BorderRadius.circular(3),
                            ),
                          );
                        }),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<Map<HymnCollection, int>> _countsFuture;
  late Future<TodaysVerse?> _todayVerseFuture;
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  void initState() {
    super.initState();
    _countsFuture = hymnRepository.collectionCounts();
    _todayVerseFuture = fetchTodaysVerse();
    _checkForUpdate();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowWhatsNew(context));
  }

  Future<void> _checkForUpdate() async {
    final result = await fetchLatestVersion();
    if (result != null && mounted && _isNewerVersion(result.version, appVersion)) {
      _showUpdateBanner(result.version, result.notes);
    }
  }

  void _showUpdateBanner(String latest, String notes) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showMaterialBanner(
      MaterialBanner(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        leading: const Icon(Icons.system_update_rounded, color: _gold),
        backgroundColor: _isDark(context) ? _nightSurface : _paper,
        dividerColor: Colors.transparent,
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Version $latest is available!',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            if (notes.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                notes,
                style: TextStyle(color: _mutedColor(context), fontSize: 12),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              ScaffoldMessenger.of(context).hideCurrentMaterialBanner();
              _scaffoldKey.currentState?.openDrawer();
            },
            child: const Text('View'),
          ),
          TextButton(
            onPressed: () => ScaffoldMessenger.of(context).hideCurrentMaterialBanner(),
            child: const Text('Dismiss'),
          ),
        ],
      ),
    );
  }


  void _refreshCounts() {
    final next = hymnRepository.collectionCounts();
    setState(() {
      _countsFuture = next;
    });
  }

  Future<void> _openCollection(HymnCollection collection) async {
    if (collection.isComingSoon) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('English hymns coming soon!'),
          backgroundColor: collection.color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HymnListScreen(collection: collection),
      ),
    );
    if (mounted) {
      _refreshCounts();
    }
  }

  Future<void> _openMembershipRegistration() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const RegistrationWebViewScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      drawer: AppSettingsDrawer(
        onReadingLangChanged: () => setState(() {
          _todayVerseFuture = fetchTodaysVerse();
        }),
        onMembershipRegistration: _openMembershipRegistration,
      ),
      body: PremiumBackground(
        child: SafeArea(
          left: false,
          right: false,
          child: FutureBuilder<Map<HymnCollection, int>>(
            future: _countsFuture,
            builder: (context, snapshot) {
              final counts = snapshot.data ?? const <HymnCollection, int>{};

              return Column(
                children: [
                  Expanded(
                    child: CustomScrollView(
                      slivers: [
                        SliverToBoxAdapter(
                          child: HomeHeader(
                            onMenuTap: () => _scaffoldKey.currentState?.openDrawer(),
                          ),
                        ),
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
                          sliver: SliverList.list(
                            children: [
                              _DailyReadingCard(verseFuture: _todayVerseFuture),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: _MiniCollectionCard(
                                      collection: HymnCollection.chichewa,
                                      count: counts[HymnCollection.chichewa],
                                      onOpen: () => _openCollection(HymnCollection.chichewa),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _MiniCollectionCard(
                                      collection: HymnCollection.tumbuka,
                                      count: counts[HymnCollection.tumbuka],
                                      onOpen: () => _openCollection(HymnCollection.tumbuka),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _MiniCollectionCard(
                                      collection: HymnCollection.english,
                                      count: counts[HymnCollection.english],
                                      onOpen: () => _openCollection(HymnCollection.english),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _MiniCollectionCard(
                                      collection: HymnCollection.favourites,
                                      count: counts[HymnCollection.favourites],
                                      onOpen: () => _openCollection(HymnCollection.favourites),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _MembershipCampaignBanner(
                                onTap: _openMembershipRegistration,
                              ),
                              const SizedBox(height: 10),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const AppFooter(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class HomeHeader extends StatelessWidget {
  const HomeHeader({required this.onMenuTap, super.key});

  final VoidCallback onMenuTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D2B7A), _navy, Color(0xFF1565C0)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          bottomLeft: Radius.circular(28),
          bottomRight: Radius.circular(28),
        ),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.30),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned.fill(child: SanctuaryArt()),
          Positioned(
            bottom: 0, left: 0, right: 0,
            child: Container(
              height: 3,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, _gold, Colors.transparent],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 16, 20),
            child: Row(
              children: [
                const LogoMark(size: 52),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          brandTitle,
                          maxLines: 1,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                                height: 1,
                              ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        appTagline,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Color(0xFFBDD0F8),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          height: 1.1,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                HeaderActionButton(
                  tooltip: 'Settings & Info',
                  icon: Icons.menu_rounded,
                  onPressed: onMenuTap,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class AppSettingsDrawer extends StatelessWidget {
  const AppSettingsDrawer({
    required this.onReadingLangChanged,
    this.onMembershipRegistration,
    super.key,
  });

  final VoidCallback onReadingLangChanged;
  final VoidCallback? onMembershipRegistration;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final bg = dark ? _nightSurface : _paper;
    final textColor = _textColor(context);
    final muted = _mutedColor(context);

    return Drawer(
      backgroundColor: bg,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0D2B7A), _navy, Color(0xFF1565C0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  const LogoMark(size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          brandTitle,
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          appTagline,
                          style: TextStyle(
                            color: const Color(0xFFBDD0F8),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  _DrawerTile(
                    icon: dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                    title: dark ? 'Day mode' : 'Night mode',
                    onTap: () {
                      appTheme.toggle();
                      Navigator.of(context).pop();
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.translate_rounded,
                    title: readingLangNotifier.value == 'chichewa'
                        ? 'Language: Chichewa'
                        : 'Language: English',
                    onTap: () {
                      final newLang = readingLangNotifier.value == 'chichewa'
                          ? 'english'
                          : 'chichewa';
                      _saveReadingLang(newLang);
                      onReadingLangChanged();
                      Navigator.of(context).pop();
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.format_size_rounded,
                    title: 'Font size',
                    trailing: Text(
                      '${(fontSizeNotifier.value * 100).toInt()}%',
                      style: TextStyle(color: muted, fontSize: 13),
                    ),
                    onTap: () {
                      final newSize = fontSizeNotifier.value == 1.0
                          ? 1.15
                          : fontSizeNotifier.value == 1.15
                              ? 1.30
                              : 0.85;
                      _saveFontSize(newSize);
                      Navigator.of(context).pop();
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.share_rounded,
                    title: 'Share app',
                    onTap: () {
                      Navigator.of(context).pop();
                      launchUrl(Uri.parse(_apkPureUrl));
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.how_to_reg_rounded,
                    title: 'Membership Registration',
                    onTap: () {
                      Navigator.of(context).pop();
                      onMembershipRegistration?.call();
                    },
                  ),
                  _DrawerTile(
                    icon: Icons.info_outline_rounded,
                    title: 'About',
                    onTap: () {
                      Navigator.of(context).pop();
                      showAppInfo(context);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerTile extends StatelessWidget {
  const _DrawerTile({
    required this.icon,
    required this.title,
    this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final textColor = _textColor(context);

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 22),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(color: textColor, fontSize: 15),
              ),
            ),
            if (trailing != null) ...[
              trailing!,
              const SizedBox(width: 8),
            ],
            Icon(
              Icons.chevron_right_rounded,
              color: _mutedColor(context),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class HeaderActionButton extends StatelessWidget {
  const HeaderActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(8),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: SizedBox(
            width: 38,
            height: 38,
            child: Icon(icon, color: Colors.white, size: 21),
          ),
        ),
      ),
    );
  }
}

class ThemeToggleIconButton extends StatelessWidget {
  const ThemeToggleIconButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: appTheme.isDark ? 'Switch to day mode' : 'Switch to night mode',
      onPressed: appTheme.toggle,
      icon: Icon(
        appTheme.isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
      ),
    );
  }
}

class CollectionPanel extends StatelessWidget {
  const CollectionPanel({
    required this.collection,
    required this.count,
    required this.onOpen,
    super.key,
  });

  final HymnCollection collection;
  final int? count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final countText = count == null
        ? '...'
        : collection == HymnCollection.favourites
        ? '$count saved'
        : '$count songs';
    final muted = _mutedColor(context);

    return Material(
      color: _surfaceColor(context, alpha: 0.96),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: _lineColor(context)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(width: 6, color: collection.color),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(15),
                    child: Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: collection.color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            collection.icon,
                            color: collection.color,
                            size: 29,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      collection.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w900,
                                          ),
                                    ),
                                  ),
                                  Text(
                                    countText,
                                    style: TextStyle(
                                      color: collection.color,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 5),
                              Text(
                                collection.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: muted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Icon(
                                    Icons.check_circle_rounded,
                                    size: 16,
                                    color: collection.color,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      collection == HymnCollection.favourites
                                          ? 'Tap to review marked hymns'
                                          : 'Tap to open the hymn list',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: muted,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: collection.color.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            Icons.arrow_forward_rounded,
                            color: collection.color,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Daily Reading Card ─────────────────────────────────────────────────────
class _DailyReadingCard extends StatefulWidget {
  const _DailyReadingCard({required this.verseFuture});
  final Future<TodaysVerse?> verseFuture;

  @override
  State<_DailyReadingCard> createState() => _DailyReadingCardState();
}

class _DailyReadingCardState extends State<_DailyReadingCard> {
  final _pageController = PageController();
  int _currentPage = 0;

  static const _charsPerPage = 400;

  static String _formatDate(DateTime d) {
    const months = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ];
    const days = ['Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday'];
    return '${days[d.weekday - 1]}, ${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  List<String> _paginate(String text) {
    if (text.length <= _charsPerPage) return [text];
    final pages = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = (start + _charsPerPage).clamp(0, text.length);
      // Break at word boundary
      if (end < text.length) {
        final space = text.lastIndexOf(' ', end);
        if (space > start) end = space;
      }
      pages.add(text.substring(start, end).trim());
      start = end;
    }
    return pages;
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final today = DateTime.now();
    return FutureBuilder<TodaysVerse?>(
      future: widget.verseFuture,
      builder: (context, snapshot) {
        final verse = snapshot.data;
        final pages = verse != null ? _paginate(verse.text) : <String>[];
        final multiPage = pages.length > 1;

        return Material(
          color: _surfaceColor(context, alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: _lineColor(context)),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: _gold.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _gold.withValues(alpha: 0.35)),
                      ),
                      child: const Icon(Icons.book_rounded, color: _gold, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _formatDate(today),
                            style: TextStyle(
                              color: _isDark(context) ? _nightMuted : _muted,
                              fontWeight: FontWeight.w900,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            verse == null
                                ? (snapshot.connectionState == ConnectionState.waiting
                                    ? 'Loading...'
                                    : 'Reading unavailable')
                                : verse.reference,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: _textColor(context),
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                if (verse != null) ...[
                  const SizedBox(height: 12),
                  // Paged text area
                  SizedBox(
                    height: 160,
                    child: PageView.builder(
                      controller: _pageController,
                      itemCount: pages.length,
                      onPageChanged: (i) => setState(() => _currentPage = i),
                      itemBuilder: (context, i) => SingleChildScrollView(
                        child: Text(
                          pages[i],
                          style: TextStyle(
                            color: _textColor(context),
                            fontWeight: FontWeight.w600,
                            height: 1.55,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                  // Footer: translation badge + page dots
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _gold.withValues(alpha: 0.30)),
                        ),
                        child: Text(
                          verse.translation.toUpperCase(),
                          style: TextStyle(
                            color: _isDark(context) ? _gold : _navy,
                            fontWeight: FontWeight.w800,
                            fontSize: 10,
                          ),
                        ),
                      ),
                      if (multiPage) ...[
                        const Spacer(),
                        // Prev
                        if (_currentPage > 0)
                          GestureDetector(
                            onTap: () => _pageController.previousPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                            ),
                            child: Icon(Icons.chevron_left_rounded,
                                color: _isDark(context) ? _gold : _navy, size: 22),
                          ),
                        const SizedBox(width: 4),
                        Text(
                          '${_currentPage + 1} / ${pages.length}',
                          style: TextStyle(
                            color: _mutedColor(context),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(width: 4),
                        // Next
                        if (_currentPage < pages.length - 1)
                          GestureDetector(
                            onTap: () => _pageController.nextPage(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeInOut,
                            ),
                            child: Icon(Icons.chevron_right_rounded,
                                color: _isDark(context) ? _gold : _navy, size: 22),
                          ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

// ── Mini collection card (half-width, compact) ─────────────────────────────
class _MiniCollectionCard extends StatelessWidget {
  const _MiniCollectionCard({
    required this.collection,
    required this.count,
    required this.onOpen,
  });

  final HymnCollection collection;
  final int? count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final countText = count == null
        ? (collection.isComingSoon ? 'Coming Soon' : '...')
        : collection == HymnCollection.favourites
        ? '$count saved'
        : '$count songs';

    return Material(
      color: _surfaceColor(context, alpha: 0.96),
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: _lineColor(context)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: collection.color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(10),
                      bottomLeft: Radius.circular(10),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: collection.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(collection.icon, color: collection.color, size: 19),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          collection.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: _textColor(context),
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          countText,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: collection.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Membership registration campaign banner ────────────────────────────
class _MembershipCampaignBanner extends StatelessWidget {
  const _MembershipCampaignBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Color(0xFF0D2B7A).withValues(alpha: dark ? 0.85 : 0.75),
              Color(0xFF1565C0).withValues(alpha: dark ? 0.75 : 0.65),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: Color(0xFFBDD0F8).withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(
                Icons.how_to_reg_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Open Your ZAG membership Profile',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'to be approved by your Homecell Pastor',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lembetsani umembala wanu ku mpingo wa Zomba Assemblies ndipo a busa aku Mlaga wanu akubvomerezani',
                    style: TextStyle(
                      color: Color(0xFFBDD0F8),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_rounded,
              color: Colors.white.withValues(alpha: 0.8),
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Featured collection card (large hero style) ────────────────────────
class _FeaturedCollectionCard extends StatelessWidget {
  const _FeaturedCollectionCard({
    required this.collection,
    required this.count,
    required this.onOpen,
  });

  final HymnCollection collection;
  final int? count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final countText = count == null
        ? (collection.isComingSoon ? 'Coming Soon' : '...')
        : collection == HymnCollection.favourites
        ? '$count saved'
        : '$count songs';
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: collection.isComingSoon
                  ? [collection.color.withValues(alpha: 0.55), collection.color.withValues(alpha: 0.35)]
                  : [
                      collection.color,
                      Color.lerp(collection.color, const Color(0xFF0A1A4A), 0.35)!,
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: collection.color.withValues(alpha: 0.28),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Stack(
            children: [
              const Positioned.fill(child: SanctuaryArt()),
              Positioned(
                top: 0, bottom: 0, left: 0,
                child: Container(width: 5, color: _gold),
              ),
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
                      ),
                      child: Icon(collection.icon, color: _gold, size: 34),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            collection.label,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              height: 1.1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            collection.subtitle,
                            style: const TextStyle(
                              color: Color(0xFFEDE7B4),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              countText,
                              style: const TextStyle(
                                color: _gold,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.arrow_forward_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Compact collection card (half-width) ──────────────────────────────
class _CompactCollectionCard extends StatelessWidget {
  const _CompactCollectionCard({
    required this.collection,
    required this.count,
    required this.onOpen,
  });

  final HymnCollection collection;
  final int? count;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final countText = count == null
        ? (collection.isComingSoon ? 'Coming Soon' : '...')
        : collection == HymnCollection.favourites
        ? '$count saved'
        : '$count songs';

    return Material(
      color: _surfaceColor(context, alpha: 0.96),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: _lineColor(context)),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: _ink.withValues(alpha: _isDark(context) ? 0.18 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: IntrinsicHeight(
            child: Row(
              children: [
                Container(
                  width: 5,
                  decoration: BoxDecoration(
                    color: collection.color,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(14),
                      bottomLeft: Radius.circular(14),
                    ),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: collection.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(collection.icon, color: collection.color, size: 22),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          collection.label,
                          style: TextStyle(
                            color: _textColor(context),
                            fontWeight: FontWeight.w900,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          countText,
                          style: TextStyle(
                            color: collection.color,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AppFooter extends StatelessWidget {
  const AppFooter({super.key});

  @override
  Widget build(BuildContext context) {
    final muted = _mutedColor(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 2,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, _gold, Color(0xFF1565C0), Colors.transparent],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.copyright_rounded, size: 14, color: muted),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  '2026 Zomba Assemblies of God · ZAG Media Team',
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class HymnListScreen extends StatefulWidget {
  const HymnListScreen({required this.collection, super.key});

  final HymnCollection collection;

  @override
  State<HymnListScreen> createState() => _HymnListScreenState();
}

class _HymnListScreenState extends State<HymnListScreen> {
  final _searchController = TextEditingController();
  List<Hymn> _hymns = const [];
  List<Hymn> _filtered = const [];
  Set<String> _favourites = const {};
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filter);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final values = await hymnRepository.hymnsFor(widget.collection);
      final favourites = await FavouriteStore.instance.ids();
      if (!mounted) {
        return;
      }
      setState(() {
        _hymns = values;
        _filtered = _applyFilter(values, _searchController.text);
        _favourites = favourites;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  void _filter() {
    setState(() => _filtered = _applyFilter(_hymns, _searchController.text));
  }

  List<Hymn> _applyFilter(List<Hymn> source, String value) {
    final tokens = _searchTokens(value);
    if (tokens.isEmpty) {
      return source;
    }
    return _rankedMatches(source, tokens).map((match) => match.hymn).toList();
  }

  List<HymnSearchMatch> _rankedMatches(List<Hymn> source, List<String> tokens) {
    final matches = <HymnSearchMatch>[];

    for (final hymn in source) {
      final searchable = hymn.searchable;
      if (!tokens.every(searchable.contains)) {
        continue;
      }

      var score = 0;
      for (final token in tokens) {
        if (hymn.number.toLowerCase() == token) {
          score += 80;
        }
        if (hymn.searchableTitle.startsWith(token)) {
          score += 40;
        }
        if (hymn.searchableTitle.contains(token)) {
          score += 24;
        }
        score += 8;
      }

      matches.add(HymnSearchMatch(hymn, score));
    }

    matches.sort((a, b) {
      final score = b.score.compareTo(a.score);
      if (score != 0) {
        return score;
      }
      return _hymnNumberSort(a.hymn.number, b.hymn.number);
    });

    return matches;
  }

  Future<void> _toggleFavourite(Hymn hymn) async {
    await FavouriteStore.instance.toggle(hymn.id);
    final favourites = await FavouriteStore.instance.ids();
    if (!mounted) {
      return;
    }
    setState(() {
      _favourites = favourites;
      if (widget.collection == HymnCollection.favourites) {
        _hymns = _hymns.where((item) => favourites.contains(item.id)).toList();
        _filtered = _applyFilter(_hymns, _searchController.text);
      }
    });
  }

  Future<void> _openHymn(Hymn hymn) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => HymnDetailScreen(
          hymn: hymn,
          favourite: _favourites.contains(hymn.id),
          onFavourite: () => _toggleFavourite(hymn),
        ),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final suggestions = _searchController.text.trim().isEmpty
        ? const <Hymn>[]
        : _filtered.take(5).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.collection.label),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: PremiumBackground(
        child: SafeArea(
          top: false,
          child: _loading
              ? LoadingState(collection: widget.collection)
              : _error != null
              ? ErrorState(message: _error!, onRetry: _load)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListHeader(
                      collection: widget.collection,
                      count: _hymns.length,
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
                      child: Column(
                        children: [
                          SearchBar(
                            controller: _searchController,
                            leading: const Icon(Icons.search_rounded),
                            hintText: 'Search number, title, or lyrics',
                            trailing: [
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  tooltip: 'Clear search',
                                  onPressed: _searchController.clear,
                                  icon: const Icon(Icons.close_rounded),
                                ),
                            ],
                          ),
                          if (suggestions.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: SuggestionPanel(
                                collection: widget.collection,
                                suggestions: suggestions,
                                onSelected: _openHymn,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: _filtered.isEmpty
                          ? EmptyState(collection: widget.collection)
                          : ListView.separated(
                              padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
                              itemCount: _filtered.length,
                              separatorBuilder: (_, i) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, index) {
                                final hymn = _filtered[index];
                                final favourite = _favourites.contains(hymn.id);
                                return HymnListTile(
                                  hymn: hymn,
                                  favourite: favourite,
                                  onFavourite: () => _toggleFavourite(hymn),
                                  onTap: () => _openHymn(hymn),
                                );
                              },
                            ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class ListHeader extends StatelessWidget {
  const ListHeader({required this.collection, required this.count, super.key});

  final HymnCollection collection;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 18, 0),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              collection.color,
              Color.lerp(collection.color, _ink, 0.22)!,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: collection.color.withValues(alpha: 0.18),
              blurRadius: 22,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
              ),
              child: Icon(collection.icon, color: _gold, size: 28),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    collection.subtitle,
                    style: const TextStyle(
                      color: Color(0xFFEFE8B4),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    collection == HymnCollection.favourites
                        ? '$count saved hymns'
                        : '$count ${collection.label} hymns',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1.05,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SuggestionPanel extends StatelessWidget {
  const SuggestionPanel({
    required this.collection,
    required this.suggestions,
    required this.onSelected,
    super.key,
  });

  final HymnCollection collection;
  final List<Hymn> suggestions;
  final ValueChanged<Hymn> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _surfaceColor(context, alpha: 0.98),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          border: Border.all(color: _lineColor(context)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var index = 0; index < suggestions.length; index++) ...[
              _SuggestionRow(
                hymn: suggestions[index],
                color: collection.color,
                onSelected: () => onSelected(suggestions[index]),
              ),
              if (index != suggestions.length - 1)
                Divider(
                  height: 1,
                  indent: 14,
                  endIndent: 14,
                  color: _lineColor(context),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SuggestionRow extends StatelessWidget {
  const _SuggestionRow({
    required this.hymn,
    required this.color,
    required this.onSelected,
  });

  final Hymn hymn;
  final Color color;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onSelected,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.north_east_rounded, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '${hymn.number}. ${hymn.title}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HymnListTile extends StatelessWidget {
  const HymnListTile({
    required this.hymn,
    required this.favourite,
    required this.onFavourite,
    required this.onTap,
    super.key,
  });

  final Hymn hymn;
  final bool favourite;
  final VoidCallback onFavourite;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final muted = _mutedColor(context);

    return Material(
      color: _surfaceColor(context, alpha: 0.96),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: _lineColor(context)),
            boxShadow: [
              BoxShadow(
                color: _ink.withValues(alpha: _isDark(context) ? 0.18 : 0.035),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(
            children: [
              HymnNumberBadge(
                number: hymn.number,
                color: hymn.collection.color,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hymn.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      hymn.lyrics
                          .replaceAll(RegExp(r'<[^>]+>'), ' ')
                          .replaceAll('&nbsp;', ' ')
                          .replaceAll(RegExp(r'\s+'), ' ')
                          .trim(),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: muted, height: 1.25),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: favourite ? 'Remove favourite' : 'Mark favourite',
                onPressed: onFavourite,
                icon: Icon(
                  favourite
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  color: favourite ? _rose : muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HymnNumberBadge extends StatelessWidget {
  const HymnNumberBadge({required this.number, required this.color, super.key});

  final String number;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = number.length <= 4 ? number : number.substring(0, 4);
    return Container(
      width: 52,
      height: 52,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 16,
        ),
      ),
    );
  }
}

class HymnDetailScreen extends StatefulWidget {
  const HymnDetailScreen({
    required this.hymn,
    required this.favourite,
    required this.onFavourite,
    super.key,
  });

  final Hymn hymn;
  final bool favourite;
  final Future<void> Function() onFavourite;

  @override
  State<HymnDetailScreen> createState() => _HymnDetailScreenState();
}

class _HymnDetailScreenState extends State<HymnDetailScreen> {
  late bool _favourite = widget.favourite;

  @override
  Widget build(BuildContext context) {
    final hymn = widget.hymn;

    return Scaffold(
      appBar: AppBar(
        title: Text('${hymn.collection == HymnCollection.chichewa ? 'Nyimbo' : hymn.collection == HymnCollection.tumbuka ? 'Sumu' : 'Hymn'} ${hymn.number}'),
        actions: [
          IconButton(
            tooltip: _favourite ? 'Remove favourite' : 'Mark favourite',
            onPressed: () async {
              await widget.onFavourite();
              if (mounted) {
                setState(() => _favourite = !_favourite);
              }
            },
            icon: Icon(
              _favourite
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              color: _favourite ? _rose : null,
            ),
          ),
        ],
      ),
      body: PremiumBackground(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 4, 18, 30),
          children: [
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    hymn.collection.color,
                    Color.lerp(
                      hymn.collection.color,
                      _isDark(context) ? _night : _ink,
                      0.20,
                    )!,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '${hymn.collection == HymnCollection.chichewa ? 'Nyimbo' : hymn.collection == HymnCollection.tumbuka ? 'Sumu' : 'Hymn'} ${hymn.number}',
                          style: const TextStyle(
                            color: _gold,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      Text(
                        hymn.collection.label,
                        style: const TextStyle(
                          color: Color(0xFFEFE8B4),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    hymn.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            if (hymn.chord != null) ...[
              InfoBand(
                icon: Icons.piano_rounded,
                label: 'Chord',
                value: hymn.chord!,
              ),
              const SizedBox(height: 14),
            ],
            HymnLyricsView(hymn: hymn),
          ],
        ),
      ),
    );
  }
}

class HymnLyricSection {
  const HymnLyricSection({
    required this.body,
    required this.isChorus,
  });

  final String body;
  final bool isChorus;
}


List<HymnLyricSection> _parseHymnSectionsUi(String lyricsHtml) {
  final input = lyricsHtml.trim();
  if (input.isEmpty) return const [];

  // Keep <br> as line breaks inside the same block.
  final normalized = input
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'\r\n|\r'), '\n');

  // Extract blocks in order: either <em>...</em> or <p>...</p>
  final blockRegex = RegExp(
    r'(<em\b[^>]*>[\s\S]*?<\/em\s*>)|(<p\b[^>]*>[\s\S]*?<\/p\s*>)',
    caseSensitive: false,
  );

  final blocks = blockRegex.allMatches(normalized).map((m) => m.group(0) ?? '').where((b) => b.isNotEmpty);

  final sections = <HymnLyricSection>[];

  for (final block in blocks) {
    final isChorus = block.toLowerCase().startsWith('<em');

    // Remove only the outer tag wrapper and then strip remaining tags.
    final inner = block
        .replaceAll(RegExp(r'^<\/?(em|p)\b[^>]*>', caseSensitive: false), '')
        .replaceAll(RegExp(r'<\/(em|p)\s*>$', caseSensitive: false), '');

    final text = inner
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('"', '"')
        .replaceAll('&#39;', "'")
        .replaceAll(RegExp(r'[ \t]+\n'), '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();

    if (text.isEmpty) continue;

    sections.add(
      HymnLyricSection(body: text, isChorus: isChorus),
    );
  }

  return sections;
}

class TodaysVerse {
  const TodaysVerse({
    required this.reference,
    required this.text,
    required this.translation,
  });

  final String reference;
  final String text;
  final String translation;
}

// ── ZAG 2026 Annual Bible Reading Calendar (Aug–Dec from PDFs) ──────────
//
// Chichewa Bible via API.Bible (free key — register at https://scripture.api.bible)
// Bible ID for The Word of God in Contemporary Chichewa (CCL): '3fa4c85c95be3aa6-01'
// Get your free API key from https://scripture.api.bible/
const _apiBibleKey = 'xuX_F26_QCgMk0-fNr6KY';
const _chichewaBibleId = '3fa4c85c95be3aa6-01';

Future<TodaysVerse?> fetchTodaysVerse() async {
  final now = DateTime.now();
  final key =
      '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

  // 1. Look up today's reading reference from the ZAG calendar JSON
  String? calendarRef;
  try {
    final raw = await rootBundle.loadString('adds/verses.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    calendarRef = map[key]?.toString().trim();
  } catch (_) {}

  const fallbacks = [
    'John 3:16', 'Psalm 23:1', 'Romans 8:28', 'Philippians 4:13',
    'Jeremiah 29:11', 'Isaiah 40:31', 'Proverbs 3:5-6', 'Matthew 6:33',
    'Romans 10:9', 'John 14:6', 'Psalm 46:1', 'Isaiah 41:10',
    'Ephesians 2:8-9', 'Romans 5:8', '2 Timothy 1:7', 'Psalm 119:105',
    'Matthew 11:28', 'John 10:10', 'Galatians 2:20', 'Hebrews 11:1',
    'James 1:2-3', '1 Corinthians 13:4-5', 'Psalm 27:1', 'Romans 12:2',
    'Colossians 3:23', 'Joshua 1:9', 'Lamentations 3:22-23', 'John 15:5',
    'Philippians 4:6-7', 'Psalm 34:8',
  ];
  final ref = calendarRef?.isNotEmpty == true
      ? calendarRef!
      : fallbacks[now.millisecondsSinceEpoch % fallbacks.length];

  final useChichewa = readingLangNotifier.value == 'chichewa';

  // 2. Try API.Bible — Chichewa (Baibulo Lopatulika 2016)
  if (useChichewa && _apiBibleKey != 'YOUR-API-BIBLE-KEY-HERE') {
    try {
      final passageId = _refToApiBibleId(ref);
      if (passageId != null) {
        final url = 'https://api.scripture.api.bible/v1/bibles/$_chichewaBibleId/passages/$passageId'
            '?content-type=text&include-notes=false&include-titles=false&include-chapter-numbers=false&include-verse-numbers=false';
        final res = await http.get(
          Uri.parse(url),
          headers: {'api-key': _apiBibleKey},
        ).timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body) as Map<String, dynamic>;
          final data = decoded['data'] as Map<String, dynamic>?;
          final content = (data?['content'] ?? '').toString()
              .replaceAll(RegExp(r'<[^>]+>'), ' ')
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
          final reference = (data?['reference'] ?? ref).toString().trim();
          if (content.isNotEmpty) {
            return TodaysVerse(
              reference: reference,
              text: content,
              translation: '2026 ZAG ANNUAL BIBLE READING PLAN',
            );
          }
        }
      }
    } catch (_) {}
  }

  // 2b. Local fallback — Chichewa verses from adds/chichewa_verses.json
  if (useChichewa) {
    try {
      final raw = await rootBundle.loadString('adds/chichewa_verses.json');
      final chichewaMap = jsonDecode(raw) as Map<String, dynamic>;
      final chichewaText = chichewaMap[ref]?.toString().trim();
      if (chichewaText != null && chichewaText.isNotEmpty) {
        return TodaysVerse(
          reference: ref,
          text: chichewaText,
          translation: '2026 ZAG ANNUAL BIBLE READING PLAN',
        );
      }
    } catch (_) {}
  }

  // 3. Fallback / English — WEB via bible-api.com
  final url = 'https://bible-api.com/${Uri.encodeComponent(ref)}?translation=web';
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final reference = (decoded['reference'] ?? '').toString().trim();
    final text = (decoded['text'] ?? '').toString().trim();
    if (reference.isEmpty || text.isEmpty) return null;
    return TodaysVerse(reference: reference, text: text, translation: '2026 ZAG ANNUAL BIBLE READING PLAN');
  } catch (_) {
    return null;
  }
}

// Converts a human reference like "John 3:16" or "Romans 8:28-29" to
// an API.Bible passage ID like "JHN.3.16" or "ROM.8.28-ROM.8.29".
String? _refToApiBibleId(String ref) {
  const bookMap = {
    'genesis': 'GEN', 'exodus': 'EXO', 'leviticus': 'LEV', 'numbers': 'NUM',
    'deuteronomy': 'DEU', 'joshua': 'JOS', 'judges': 'JDG', 'ruth': 'RUT',
    '1 samuel': '1SA', '2 samuel': '2SA', '1 kings': '1KI', '2 kings': '2KI',
    '1 chronicles': '1CH', '2 chronicles': '2CH', 'ezra': 'EZR',
    'nehemiah': 'NEH', 'esther': 'EST', 'job': 'JOB', 'psalm': 'PSA',
    'psalms': 'PSA', 'proverbs': 'PRO', 'ecclesiastes': 'ECC',
    'song of solomon': 'SNG', 'isaiah': 'ISA', 'jeremiah': 'JER',
    'lamentations': 'LAM', 'ezekiel': 'EZK', 'daniel': 'DAN', 'hosea': 'HOS',
    'joel': 'JOL', 'amos': 'AMO', 'obadiah': 'OBA', 'jonah': 'JON',
    'micah': 'MIC', 'nahum': 'NAH', 'habakkuk': 'HAB', 'zephaniah': 'ZEP',
    'haggai': 'HAG', 'zechariah': 'ZEC', 'malachi': 'MAL',
    'matthew': 'MAT', 'mark': 'MRK', 'luke': 'LUK', 'john': 'JHN',
    'acts': 'ACT', 'romans': 'ROM', '1 corinthians': '1CO',
    '2 corinthians': '2CO', 'galatians': 'GAL', 'ephesians': 'EPH',
    'philippians': 'PHP', 'colossians': 'COL', '1 thessalonians': '1TH',
    '2 thessalonians': '2TH', '1 timothy': '1TI', '2 timothy': '2TI',
    'titus': 'TIT', 'philemon': 'PHM', 'hebrews': 'HEB', 'james': 'JAS',
    '1 peter': '1PE', '2 peter': '2PE', '1 john': '1JN', '2 john': '2JN',
    '3 john': '3JN', 'jude': 'JUD', 'revelation': 'REV',
  };

  // Match: "Book Chapter:Verse" or "Book Chapter:Verse-EndVerse" or "Book Chapter"
  final match = RegExp(
    r'^(.+?)\s+(\d+)(?::(\d+)(?:-(\d+))?)?$',
    caseSensitive: false,
  ).firstMatch(ref.trim());
  if (match == null) return null;

  final bookKey = match.group(1)!.trim().toLowerCase();
  final chapter = match.group(2)!;
  final verseStart = match.group(3);
  final verseEnd = match.group(4);
  final bookCode = bookMap[bookKey];
  if (bookCode == null) return null;

  if (verseStart == null) {
    // Whole chapter
    return '$bookCode.$chapter';
  }
  if (verseEnd == null) {
    return '$bookCode.$chapter.$verseStart';
  }
  return '$bookCode.$chapter.$verseStart-$bookCode.$chapter.$verseEnd';
}

const _whatsNewKey = 'whats_new_seen_v1.7';

const _whatsNewItems = [
  (icon: Icons.settings_rounded,          text: 'New Settings sidebar — all controls in one place'),
  (icon: Icons.translate_rounded,         text: 'Bible reading language: choose Chichewa or English'),
  (icon: Icons.format_size_rounded,       text: 'Global font size control in Settings'),
  (icon: Icons.dark_mode_rounded,         text: 'Dark/light mode toggle moved to Settings sidebar'),
  (icon: Icons.share_rounded,             text: 'Share the app directly from Settings'),
  (icon: Icons.system_update_rounded,     text: 'Update banner — notified when a new version is out'),
];

Future<void> _maybeShowWhatsNew(BuildContext context) async {
  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(_whatsNewKey) == true) return;
  await prefs.setBool(_whatsNewKey, true);
  if (!context.mounted) return;
  _showWhatsNewDialog(context);
}

void _showWhatsNewDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _WhatsNewDialog(),
  );
}

class _WhatsNewDialog extends StatelessWidget {
  const _WhatsNewDialog();

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 22, vertical: 32),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        decoration: BoxDecoration(
          color: dark ? _nightSurface : _paper,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 22, 20, 18),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFF0D2B7A), _navy, const Color(0xFF1565C0)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _gold.withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _gold.withValues(alpha: 0.50)),
                        ),
                        child: Text(
                          'VERSION $appVersion',
                          style: const TextStyle(
                            color: _gold,
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    "What's New 🎉",
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Here is what changed in this update',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.70),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Items
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                child: Column(
                  children: [
                    for (final item in _whatsNewItems)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36, height: 36,
                              decoration: BoxDecoration(
                                color: _navy.withValues(alpha: dark ? 0.35 : 0.08),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Icon(item.icon, color: dark ? _gold : _navy, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8),
                                child: Text(
                                  item.text,
                                  style: TextStyle(
                                    color: dark ? _nightText : _ink,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    height: 1.35,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Footer
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: FilledButton.styleFrom(
                    backgroundColor: _navy,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    "Let's Go!",
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
const _versionJsonUrl =
    'https://raw.githubusercontent.com/zagmedia/zaghymn/main/version.json';
const _apkPureUrl = 'https://apkpure.com/zag-nyimbo-za-chitsitsimutso/com.zagmedia.zaghymn';

Future<({String version, String notes})?> fetchLatestVersion() async {
  try {
    final res = await http
        .get(Uri.parse(_versionJsonUrl))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode != 200) return null;
    final decoded = jsonDecode(res.body) as Map<String, dynamic>;
    final version = decoded['version']?.toString().trim();
    final notes = decoded['releaseNotes']?.toString().trim() ?? '';
    if (version == null) return null;
    return (version: version, notes: notes);
  } catch (_) {
    return null;
  }
}

bool _isNewerVersion(String latest, String current) {
  final l = latest.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  final c = current.split('.').map((e) => int.tryParse(e) ?? 0).toList();
  for (var i = 0; i < math.max(l.length, c.length); i++) {
    final lv = i < l.length ? l[i] : 0;
    final cv = i < c.length ? c[i] : 0;
    if (lv > cv) return true;
    if (lv < cv) return false;
  }
  return false;
}

void _showUpdateDialog(BuildContext context, String latestVersion) {
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: _isDark(context) ? _nightSurface : _paper,
      title: Row(
        children: [
          Icon(Icons.system_update_rounded, color: _gold, size: 22),
          const SizedBox(width: 10),
          const Text('Update Available', style: TextStyle(fontWeight: FontWeight.w900)),
        ],
      ),
      content: Text(
        'Version $latestVersion is available on APKPure.\nYou are on v$appVersion.',
        style: TextStyle(color: _mutedColor(context), height: 1.5),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Later'),
        ),
        FilledButton.icon(
          onPressed: () {
            Navigator.of(context).pop();
            // url_launcher would open the APKPure page
            // launchUrl(Uri.parse(_apkPureUrl));
          },
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Get Update'),
        ),
      ],
    ),
  );
}

class HymnLyricsView extends StatefulWidget {
  const HymnLyricsView({required this.hymn, super.key});


  final Hymn hymn;

  @override
  State<HymnLyricsView> createState() => _HymnLyricsViewState();
}

class _HymnLyricsViewState extends State<HymnLyricsView> {
  // Zoom control (slider)
  double _zoom = 1.0;

  double get _fontScale => _zoom.clamp(0.85, 1.25);

  @override
  Widget build(BuildContext context) {
    final sections = _parseHymnSectionsUi(widget.hymn.lyrics);

    final baseFontSize = 17.0;
    final fontSize = baseFontSize * _fontScale;

    final headerColor = _isDark(context) ? _nightMuted : _muted;
    final cardBorder = _lineColor(context);

    return Material(
      color: _surfaceColor(context, alpha: 0.96),
      borderRadius: BorderRadius.circular(8),
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: cardBorder),
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (sections.isNotEmpty) ...[
              Row(
                children: [
                  Icon(
                    Icons.menu_book_rounded,
                    size: 18,
                    color: _isDark(context) ? _gold : _green,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Lyrics view',
                    style: TextStyle(
                      color: headerColor,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                  const Spacer(),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 200),
                    child: Row(
                      children: [
                        Text(
                          '${(_zoom * 100).round()}%',
                          style: TextStyle(
                            color: headerColor,
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 2,
                              thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 7,
                              ),
                            ),
                            child: Slider(
                              value: _zoom,
                              min: 0.85,
                              max: 1.25,
                              divisions: 40,
                              label: '${(_zoom * 100).round()}%',
                              onChanged: (v) {
                                setState(() => _zoom = v);
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
            ],
            sections.isEmpty
                ? _TextBlock(
                    text: widget.hymn.lyrics,
                    fontSize: fontSize,
                    weight: FontWeight.w600,
                  )
                : _LyricsParagraphs(
                    sections: sections,
                    fontSize: fontSize,
                  ),
          ],
        ),
      ),
    );
  }
}

class _LyricsParagraphs extends StatelessWidget {
  const _LyricsParagraphs({
    required this.sections,
    required this.fontSize,
  });

  final List<HymnLyricSection> sections;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          _SectionBlock(
            section: sections[i],
            fontSize: fontSize,
          ),
          // Gap between sections (paragraph ↔ em), compact within same type.
          if (i < sections.length - 1)
            SizedBox(height: sections[i].isChorus != sections[i + 1].isChorus ? 18 : 10),
        ],
      ],
    );
  }
}

class _SectionBlock extends StatelessWidget {
  const _SectionBlock({required this.section, required this.fontSize});

  final HymnLyricSection section;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final lines = section.body.split('\n').where((l) => l.trim().isNotEmpty).toList();
    final color = _textColor(context);
    final weight = section.isChorus ? FontWeight.w700 : FontWeight.w600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var j = 0; j < lines.length; j++) ...[
          SelectableText(
            lines[j],
            style: TextStyle(
              fontSize: fontSize,
              color: color,
              fontWeight: weight,
              fontStyle: section.isChorus ? FontStyle.italic : FontStyle.normal,
              height: 1.15,
            ),
          ),
          // Compact spacing between lines of the same section.
          if (j < lines.length - 1) const SizedBox(height: 1),
        ],
      ],
    );
  }
}


class _TextBlock extends StatelessWidget {
  const _TextBlock({
    required this.text,
    required this.fontSize,
    required this.weight,
  });

  final String text;
  final double fontSize;
  final FontWeight weight;

  @override
  Widget build(BuildContext context) {
    return _CenteredLyricText(
      text,
      color: _textColor(context),
      weight: weight,
      fontSize: fontSize,
      textAlign: TextAlign.left,
    );
  }
}



class _CenteredLyricText extends StatelessWidget {
  const _CenteredLyricText(
    this.value, {
    required this.color,
    required this.weight,
    required this.fontSize,
    this.textAlign,
  });

  final String value;
  final Color color;
  final FontWeight weight;
  final double fontSize;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return SelectableText(
      value,
      textAlign: textAlign ?? TextAlign.center,
      style: TextStyle(
        height: 1.18,
        fontSize: fontSize,
        color: color,
        fontWeight: weight,
      ),
    );
  }
}

class InfoBand extends StatelessWidget {
  const InfoBand({
    required this.icon,
    required this.label,
    required this.value,
    super.key,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _gold.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: _isDark(context) ? _gold : _navy),
          const SizedBox(width: 12),
          Text(
            '$label: ',
            style: TextStyle(
              color: _mutedColor(context),
              fontWeight: FontWeight.w800,
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: _textColor(context),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void showAppInfo(BuildContext context) {
  showDialog<void>(context: context, builder: (_) => const AppInfoDialog());
}

class AppInfoDialog extends StatelessWidget {
  const AppInfoDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 460, maxHeight: maxHeight),
        child: ColoredBox(
          color: dark ? _night : _paper,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── Close button ─────────────────────────────────────────
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => Navigator.of(context).pop(),
                      child: SizedBox(
                        width: 34, height: 34,
                        child: Icon(Icons.close_rounded, color: _mutedColor(context), size: 18),
                      ),
                    ),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // ── Developer message ─────────────────────────────
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              _gold.withValues(alpha: dark ? 0.18 : 0.12),
                              _green.withValues(alpha: dark ? 0.12 : 0.07),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: _gold.withValues(alpha: 0.30),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(Icons.favorite_rounded, color: _rose, size: 15),
                                const SizedBox(width: 7),
                                Text(
                                  'A message from the developers',
                                  style: TextStyle(
                                    color: dark ? _gold : _navy,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'This app was built with love and dedication to serve the '
                              'Zomba Assemblies of God congregation. May these hymns '
                              'draw you closer to God and enrich your worship. '
                              'We pray this tool blesses every heart that uses it.',
                              style: TextStyle(
                                color: _textColor(context),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                height: 1.55,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              '— ZAG Media Team',
                              style: TextStyle(
                                color: dark ? _gold : _green,
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),

                      // ── App details ───────────────────────────────────
                      _InfoLabel('About'),
                      const SizedBox(height: 8),
                      _InfoGrid([
                        _InfoCell(icon: Icons.tag_rounded, label: 'Version', value: appVersion),
                        _InfoCell(icon: Icons.verified_rounded, label: 'Copyright', value: '© 2026 ZAG'),
                        _InfoCell(icon: Icons.church_rounded, label: 'Senior Pastor', value: 'Rev Symon Msisya'),
                        _InfoCell(
                          icon: Icons.person_rounded,
                          label: 'Lead Dev',
                          value: 'Leonard JJ Mhone',
                          onTap: () {
                            final message = Uri.encodeComponent('Hello from ZAG Hymns APP');
                            launchUrl(Uri.parse('https://wa.me/265992919716?text=$message'));
                          },
                        ),
                        _InfoCell(icon: Icons.groups_rounded, label: 'Team', value: 'ZAG Media Team'),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InfoLabel extends StatelessWidget {
  const _InfoLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(width: 3, height: 14, color: _gold, margin: const EdgeInsets.only(right: 8)),
        Text(
          text.toUpperCase(),
          style: TextStyle(
            color: _mutedColor(context),
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

class _InfoCell {
  const _InfoCell({required this.icon, required this.label, required this.value, this.onTap});
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid(this.cells);
  final List<_InfoCell> cells;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _InfoGridCell(cell: cells[0])),
            const SizedBox(width: 8),
            Expanded(child: _InfoGridCell(cell: cells[1])),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _InfoGridCell(cell: cells[2])),
            const SizedBox(width: 8),
            Expanded(child: _InfoGridCell(cell: cells[3])),
          ],
        ),
        const SizedBox(height: 8),
        _InfoGridCell(cell: cells[4]),
      ],
    );
  }
}

class _InfoGridCell extends StatelessWidget {
  const _InfoGridCell({required this.cell});
  final _InfoCell cell;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: _surfaceColor(context, alpha: 0.80),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _lineColor(context)),
      ),
      child: Row(
        children: [
          Icon(cell.icon, size: 16, color: dark ? _gold : _navy),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  cell.label,
                  style: TextStyle(color: _mutedColor(context), fontSize: 10, fontWeight: FontWeight.w800),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                Text(
                  cell.value,
                  style: TextStyle(color: _textColor(context), fontSize: 12, fontWeight: FontWeight.w900),
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (cell.onTap != null) {
      return InkWell(
        onTap: cell.onTap,
        borderRadius: BorderRadius.circular(10),
        child: content,
      );
    }

    return content;
  }
}

class RegistrationWebViewScreen extends StatefulWidget {
  const RegistrationWebViewScreen({super.key});

  @override
  State<RegistrationWebViewScreen> createState() => _RegistrationWebViewScreenState();
}

class _RegistrationWebViewScreenState extends State<RegistrationWebViewScreen> {
  late final WebViewController _controller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) => setState(() => _loading = true),
          onPageFinished: (_) => setState(() => _loading = false),
        ),
      )
      ..loadRequest(Uri.parse('https://zombaassemblies.ct.ws/'));
  }

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Membership Registration'),
        backgroundColor: dark ? _night : _paper,
        foregroundColor: _textColor(context),
        elevation: 0,
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_loading)
            const Center(
              child: CircularProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class LoadingState extends StatelessWidget {
  const LoadingState({required this.collection, super.key});

  final HymnCollection collection;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: collection.color),
          const SizedBox(height: 16),
          Text(
            'Loading ${collection.label} hymns...',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.collection, super.key});

  final HymnCollection collection;

  @override
  Widget build(BuildContext context) {
    final message = collection == HymnCollection.favourites
        ? 'No favourite hymns yet.'
        : 'No hymns found in this collection.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(collection.icon, size: 46, color: collection.color),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class ErrorState extends StatelessWidget {
  const ErrorState({required this.message, required this.onRetry, super.key});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 44, color: _rose),
            const SizedBox(height: 12),
            Text(
              'Could not load hymns',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class LogoMark extends StatelessWidget {
  const LogoMark({required this.size, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Hero(
      tag: logoAsset,
      child: Container(
        width: size,
        height: size,
        padding: EdgeInsets.all(size * 0.08),
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: _navy.withValues(alpha: 0.16),
              blurRadius: size * 0.22,
              offset: Offset(0, size * 0.08),
            ),
          ],
        ),
        child: Image.asset(logoAsset, fit: BoxFit.contain),
      ),
    );
  }
}

class PremiumBackground extends StatelessWidget {
  const PremiumBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dark = _isDark(context);

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: dark ? const [_night, _nightMist] : const [_paper, _mist],
            ),
          ),
        ),
        CustomPaint(painter: HymnBackgroundPainter(dark: dark)),
        child,
      ],
    );
  }
}

class SanctuaryArt extends StatelessWidget {
  const SanctuaryArt({super.key});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: SanctuaryPainter());
  }
}

class SanctuaryPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final goldPaint = Paint()
      ..color = _gold.withValues(alpha: 0.20)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;
    final whitePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var i = 0; i < 5; i++) {
      final x = size.width * (0.58 + i * 0.08);
      final y = size.height * (0.22 + math.sin(i) * 0.12);
      canvas.drawCircle(Offset(x, y), 7, goldPaint);
      canvas.drawLine(Offset(x + 7, y), Offset(x + 7, y - 34), goldPaint);
      canvas.drawLine(Offset(x + 7, y - 34), Offset(x + 24, y - 28), goldPaint);
    }

    final chapel = Path()
      ..moveTo(size.width * 0.66, size.height * 0.98)
      ..lineTo(size.width * 0.66, size.height * 0.62)
      ..lineTo(size.width * 0.80, size.height * 0.46)
      ..lineTo(size.width * 0.94, size.height * 0.62)
      ..lineTo(size.width * 0.94, size.height * 0.98);
    canvas.drawPath(chapel, whitePaint);
    canvas.drawLine(
      Offset(size.width * 0.80, size.height * 0.46),
      Offset(size.width * 0.80, size.height * 0.28),
      whitePaint,
    );
    canvas.drawLine(
      Offset(size.width * 0.75, size.height * 0.34),
      Offset(size.width * 0.85, size.height * 0.34),
      whitePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class HymnBackgroundPainter extends CustomPainter {
  const HymnBackgroundPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final topBand = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, size.height * 0.20)
      ..quadraticBezierTo(
        size.width * 0.58,
        size.height * 0.13,
        0,
        size.height * 0.26,
      )
      ..close();
    canvas.drawPath(
      topBand,
      Paint()..color = _gold.withValues(alpha: dark ? 0.06 : 0.08),
    );

    final middleBand = Path()
      ..moveTo(0, size.height * 0.42)
      ..quadraticBezierTo(
        size.width * 0.35,
        size.height * 0.36,
        size.width,
        size.height * 0.46,
      )
      ..lineTo(size.width, size.height * 0.58)
      ..quadraticBezierTo(
        size.width * 0.58,
        size.height * 0.51,
        0,
        size.height * 0.61,
      )
      ..close();
    canvas.drawPath(
      middleBand,
      Paint()..color = _green.withValues(alpha: dark ? 0.07 : 0.04),
    );

    final linePaint = Paint()
      ..color = (dark ? _gold : _navy).withValues(alpha: dark ? 0.035 : 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (var i = 0; i < 6; i++) {
      final y = size.height * (0.18 + i * 0.11);
      final path = Path()
        ..moveTo(-20, y)
        ..quadraticBezierTo(
          size.width * 0.35,
          y + math.sin(i) * 20,
          size.width + 20,
          y - 12,
        );
      canvas.drawPath(path, linePaint);
    }

    final bottom = Path()
      ..moveTo(0, size.height * 0.86)
      ..quadraticBezierTo(
        size.width * 0.28,
        size.height * 0.80,
        size.width * 0.56,
        size.height * 0.88,
      )
      ..quadraticBezierTo(
        size.width * 0.78,
        size.height * 0.94,
        size.width,
        size.height * 0.84,
      )
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(
      bottom,
      Paint()..color = (dark ? _gold : _navy).withValues(alpha: 0.045),
    );
  }

  @override
  bool shouldRepaint(covariant HymnBackgroundPainter oldDelegate) {
    return oldDelegate.dark != dark;
  }
}

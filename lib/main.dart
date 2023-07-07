import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_web_auth/flutter_web_auth.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'dart:io' as io;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:connectivity_plus/connectivity_plus.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const SplashScreen(),
    );
  }
}

class DBHelper {
  static Database? _db;

  Future<Database> get db async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db!;
  }

  initDb() async {
    io.Directory documentDirectory = await getApplicationDocumentsDirectory();
    String dbPath = path.join(documentDirectory.path, 'mydb.db');
    var ourDb = await openDatabase(dbPath, version: 1, onCreate: _onCreate);
    return ourDb;
  }

  void _onCreate(Database db, int version) async {
    await db.execute(
        'CREATE TABLE Place(id INTEGER PRIMARY KEY, name TEXT, description TEXT, iconUrl TEXT)');
    print('Table is created');
  }

  Future<int> savePlace(Place place) async {
    var dbClient = await db;
    int res = await dbClient.insert("Place", place.toMap());
    return res;
  }

  Future<void> clearDB() async {
    var dbClient = await db;
    await dbClient.delete("Place");
    print('All Places deleted');
  }

  Future<List<Place>> getPlaces() async {
    var dbClient = await db;
    List<Map> list = await dbClient.rawQuery('SELECT * FROM Place');
    List<Place> places = [];
    for (int i = 0; i < list.length; i++) {
      var place = new Place(
        name: list[i]["name"],
        description: list[i]["description"],
        iconUrl: list[i]["iconUrl"],
      );
      places.add(place);
    }
    return places;
  }
}

class AuthService {
  Future<void> logout() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.remove('access_token');
    print('Access token removed');
  }

  static const String clientId =
      'NIM4R10UWLRHBU0UVOGTSTGY2W1M2IYYPZYVRVFMJV1GNKIA';
  static const String clientSecret =
      'UWB0CEWZJNS0TIRKFRDTHBOYV2ALD4RQSPRFXWRYJYUTBMY3';
  static const String redirectUri = 'myapp://oauth';

  Future<bool> login() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final result = await FlutterWebAuth.authenticate(
      url:
          "https://foursquare.com/oauth2/authenticate?client_id=$clientId&response_type=code&redirect_uri=$redirectUri",
      callbackUrlScheme: "myapp",
    );

    final code = Uri.parse(result).queryParameters['code'];

    final response = await http.post(
      Uri.parse(
          "https://foursquare.com/oauth2/access_token?client_id=$clientId&client_secret=$clientSecret&grant_type=authorization_code&redirect_uri=$redirectUri&code=$code"),
    );

    if (response.statusCode == 200) {
      final accessToken = jsonDecode(response.body)['access_token'];
      await prefs.setString('access_token', accessToken);
      print('Access Token: $accessToken');
      return true;
    } else {
      print(
          'Failed to load access token. Status code: ${response.statusCode}.');
      return false;
    }
  }

  Future<String> getAccessToken() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString('access_token') ?? '';
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  List<Place> places = [];
  AuthService authService = AuthService();
  DBHelper dbHelper = DBHelper();

  @override
  void initState() {
    super.initState();
    authenticateUser();
    fetchAndStorePlaces();
  }

  Future<void> fetchAndStorePlaces() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? accessToken = prefs.getString('access_token');

    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      // Нет подключения к интернету, загрузка из базы данных
      places = await dbHelper.getPlaces();
      setState(() {});
    } else {
      // Есть подключение к интернету, пропустить загрузку из сети
      var url = Uri.parse(
          'https://api.foursquare.com/v3/places/search?ll=53.9057644%2C27.5582305&radius=4000&limit=30&session_token=%24$accessToken');
      var headers = {
        'Authorization': 'fsq3QVO7e2NiBVtQ2uSBlsKKB1Zfrv0qr7Qd9V32WZvCq84=',
        'accept': 'application/json',
      };

      var response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        var jsonData = jsonDecode(response.body);
        var results = jsonData['results'];
        List<Place> places = [];
        for (var result in results) {
          var place = Place.fromJson(result);
          places.add(place);
          await dbHelper.savePlace(place); // Сохранение места в базе данных
        }
        setState(() {});
      } else {
        print('Error: ${response.statusCode}');
      }
    }
  }

  void authenticateUser() async {
    final token = await authService.getAccessToken();
    if (mounted) {
      if (token.isEmpty) {
        bool isAuthenticated = await authService.login();
        if (mounted) {
          if (isAuthenticated) {
            await fetchAndStorePlaces();
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                  builder: (context) => HomeScreen(places: places)),
            );
          }
        }
      } else {
        await fetchAndStorePlaces();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => HomeScreen(places: places)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Image.asset(
          'images/fs.png', // Путь к изображению логотипа
          width: 200,
          height: 200,
        ),
      ),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key, required List<Place> places}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  DBHelper dbHelper = DBHelper();
  AuthService authService = AuthService();
  List<Place> places = [];

  @override
  void initState() {
    super.initState();
    fetchAndStorePlaces();
  }

  Future<void> fetchAndStorePlaces() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final String? accessToken = prefs.getString('access_token');

    var connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult == ConnectivityResult.none) {
      // Нет подключения к интернету, загрузка из базы данных
      places = await dbHelper.getPlaces();
    } else {
      // Есть подключение к интернету, пропустить загрузку из сети
      var url = Uri.parse(
          'https://api.foursquare.com/v3/places/search?ll=53.9057644%2C27.5582305&radius=4000&limit=30&session_token=%24$accessToken');
      var headers = {
        'Authorization': 'fsq3QVO7e2NiBVtQ2uSBlsKKB1Zfrv0qr7Qd9V32WZvCq84=',
        'accept': 'application/json',
      };

      var response = await http.get(url, headers: headers);

      if (response.statusCode == 200) {
        var jsonData = jsonDecode(response.body);
        var results = jsonData['results'];
        List<Place> newPlaces = [];
        for (var result in results) {
          var place = Place.fromJson(result);
          newPlaces.add(place);
          await dbHelper.savePlace(place); // Сохранение места в базе данных
        }
        setState(() {
          places = newPlaces;
        });
      } else {
        print('Error: ${response.statusCode}');
      }
    }
  }

  Future<void> clearData() async {
    setState(() {
      places = [];
    });
    await dbHelper.clearDB();
    await authService.logout();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Nearby'),
        actions: <Widget>[
          IconButton(
            onPressed: clearData,
            icon: Icon(
              Icons.logout,
              color: Colors.black,
            ),
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: places.length,
        itemBuilder: (context, index) {
          var place = places[index];
          return ListTile(
            title: Text(place.name),
            subtitle: Text(place.description),
            leading: SizedBox(
              width: 48.0,
              height: 48.0,
              child: Image.network(place.iconUrl),
            ),
          );
        },
      ),
    );
  }
}

class Place {
  final String name;
  final String description;
  final String iconUrl;

  Place({
    required this.name,
    required this.description,
    required this.iconUrl,
  });

  factory Place.fromJson(Map<String, dynamic> json) {
    var categories = json['categories'];
    var category = categories[0];
    return Place(
      name: json['name'],
      description: category['name'],
      iconUrl: category['icon']['prefix'] + '88' + category['icon']['suffix'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'description': description,
      'iconUrl': iconUrl,
    };
  }
}

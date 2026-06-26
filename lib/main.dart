import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:noise_meter/noise_meter.dart'; 
import 'dart:async';


// 1. SERVICIO PROVISIONAL PARA EL BACKEND

class BackendService {
  static const String baseUrl = "http://localhost:8000";

  Future<bool> sendMeasurement(double db, double lat, double lon) async {
    print("📤 [PROVISIONAL] Enviando al backend: dB=$db, Lat=$lat, Lon=$lon");
    await Future.delayed(const Duration(seconds: 1));
    return true;
  }

  Future<List<Map<String, dynamic>>> fetchMeasurements() async {
    print("📥 [PROVISIONAL] Obteniendo datos del mapa");
    return [
      {'decibeles': 30, 'latitud': -33.452, 'longitud': -70.664},
      {'decibeles': 55, 'latitud': -33.455, 'longitud': -70.668},
      {'decibeles': 75, 'latitud': -33.450, 'longitud': -70.660},
      {'decibeles': 90, 'latitud': -33.448, 'longitud': -70.665},
    ];
  }
}


// 2. MAIN

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const QuietZoneApp());
}

class QuietZoneApp extends StatelessWidget {
  const QuietZoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QuietZone',
      theme: ThemeData.dark(useMaterial3: true),
      debugShowCheckedModeBanner: false,
      home: const AuthWrapper(),
    );
  }
}


// 3. AUTH WRAPPER

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return const HomeScreen();
        }
        return const LoginScreen();
      },
    );
  }
}


// 4. LOGIN
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  Future<void> _signInWithGoogle(BuildContext context) async {
    try {
      final GoogleSignInAccount? googleUser = await GoogleSignIn().signIn();
      if (googleUser == null) return;
      final GoogleSignInAuthentication googleAuth =
      await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await FirebaseAuth.instance.signInWithCredential(credential);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al iniciar sesión: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.teal.shade900, Colors.black87],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.volume_down_alt, size: 100, color: Colors.tealAccent),
                const SizedBox(height: 20),
                const Text('QuietZone',
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.bold,
                        color: Colors.white, letterSpacing: 2)),
                const SizedBox(height: 10),
                const Text('Monitoreo colaborativo de ruido',
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 60),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _signInWithGoogle(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30)),
                    ),
                    icon: Image.network(
                      'https://developers.google.com/identity/images/g-logo.png',
                      height: 24,
                    ),
                    label: const Text('Iniciar sesión con Google',
                        style: TextStyle(fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 30),
                const Text('Protege tu salud auditiva con la comunidad',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}


// 5. HOME (Barra de navegacion)

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  static const List<Widget> _pages = <Widget>[
    MapScreen(),
    MeasureScreen(),
    CommunityScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.grey.shade900,
        selectedItemColor: Colors.tealAccent,
        unselectedItemColor: Colors.grey,
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Mapa'),
          BottomNavigationBarItem(icon: Icon(Icons.mic), label: 'Medir'),
          BottomNavigationBarItem(icon: Icon(Icons.people), label: 'Comunidad'),
          BottomNavigationBarItem(icon: Icon(Icons.settings), label: 'Ajustes'),
        ],
      ),
    );
  }
}


// 6. MAPA
class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  final BackendService _backend = BackendService();
  late Future<List<Map<String, dynamic>>> _futureMeasurements;
  Set<Circle> _circles = {};
  LatLng _initialPosition = const LatLng(-33.452, -70.664);

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      setState(() {
        _initialPosition = LatLng(pos.latitude, pos.longitude);
      });
    } catch (e) {}
    _futureMeasurements = _backend.fetchMeasurements();
    final data = await _futureMeasurements;
    _updateCircles(data);
  }

  void _updateCircles(List<Map<String, dynamic>> data) {
    Set<Circle> newCircles = {};
    for (var item in data) {
      double db = item['decibeles'] ?? 0;
      double lat = item['latitud'] ?? 0;
      double lon = item['longitud'] ?? 0;
      if (lat == 0 || lon == 0) continue;
      Color _getColor(double db) {
        double t = (db.clamp(20, 100) - 20) / 80;
        double hue = (1 - t) * 240;
        return HSVColor.fromAHSV(1.0, hue, 1.0, 1.0).toColor();
      }
      newCircles.add(
        Circle(
          circleId: CircleId('circle_${lat}_${lon}'),
          center: LatLng(lat, lon),
          radius: 50,
          fillColor: _getColor(db).withOpacity(0.6),
          strokeColor: _getColor(db),
          strokeWidth: 2,
        ),
      );
    }
    setState(() => _circles = newCircles);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Ruido'),
        backgroundColor: Colors.teal.shade900,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              _loadData();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Actualizando mapa...')),
              );
            },
          ),
        ],
      ),
      body: GoogleMap(
        mapType: MapType.normal,
        initialCameraPosition: CameraPosition(
          target: _initialPosition,
          zoom: 14.0,
        ),
        circles: _circles,
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        zoomControlsEnabled: true,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          final parentState = context.findAncestorStateOfType<_HomeScreenState>();
          if (parentState != null) {
            parentState.setState(() => parentState._selectedIndex = 1);
          }
        },
        child: const Icon(Icons.add_location),
        backgroundColor: Colors.teal.shade700,
      ),
    );
  }
}


// 7. PANTALLA: MEDIR RUIDO

class MeasureScreen extends StatefulWidget {
  const MeasureScreen({super.key});

  @override
  State<MeasureScreen> createState() => _MeasureScreenState();
}

class _MeasureScreenState extends State<MeasureScreen> {
  final BackendService _backend = BackendService();
  final NoiseMeter _noiseMeter = NoiseMeter();
  bool _isMeasuring = false;
  double _currentDb = 0.0;
  String _locationMessage = "Esperando ubicación...";
  late Position _currentPosition;
  StreamSubscription<NoiseReading>? _subscription;

  @override
  void dispose() {

    _subscription?.cancel();
    super.dispose();
  }

  Future<void> _startMeasuring() async {
    if (_isMeasuring) return;

    // Verificar permisos de micrófono
    if (!await Permission.microphone.isGranted) {
      final status = await Permission.microphone.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Se necesita permiso de micrófono para medir ruido'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }
    }

    setState(() {
      _isMeasuring = true;
      _currentDb = 0.0;
      _locationMessage = "Obteniendo GPS...";
    });

    // Obtener ubicación
    try {
      Position pos = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high);
      _currentPosition = pos;
      setState(() {
        _locationMessage =
        "📍 Lat: ${pos.latitude.toStringAsFixed(5)}, Lon: ${pos.longitude.toStringAsFixed(5)}";
      });
    } catch (e) {
      setState(() {
        _locationMessage = "⚠️ Error GPS: $e";
        _isMeasuring = false;
      });
      return;
    }

    // Iniciar escucha del micrófono
    try {
      // Cancelar suscripción anterior si existe
      await _subscription?.cancel();

      _subscription = _noiseMeter.noise.listen(
            (NoiseReading reading) {
          if (mounted) {
            setState(() {
              _currentDb = reading.meanDecibel;
            });
          }
        },
        onError: (Object error) {
          if (mounted) {
            setState(() => _isMeasuring = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Error en el micrófono: $error')),
            );
          }
        },
      );

      // Detener después de 5 segundos
      Future.delayed(const Duration(seconds: 5), () {
        _stopMeasuring();
      });
    } catch (e) {
      setState(() => _isMeasuring = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al iniciar el micrófono: $e')),
      );
    }
  }

  void _stopMeasuring() async {
    // Solo cancelamos la suscripción
    await _subscription?.cancel();
    setState(() => _isMeasuring = false);

    if (_currentDb > 0) {
      bool success = await _backend.sendMeasurement(
        _currentDb,
        _currentPosition.latitude,
        _currentPosition.longitude,
      );
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Medición guardada: ${_currentDb.toStringAsFixed(1)} dB'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Error al guardar en el backend'),
              backgroundColor: Colors.red),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('⚠️ No se registró sonido válido'),
            backgroundColor: Colors.orange),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Medir Ruido'),
        backgroundColor: Colors.teal.shade900,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Card(
              elevation: 8,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              color: Colors.teal.shade800,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40.0),
                child: Column(
                  children: [
                    const Text('Nivel de Ruido',
                        style: TextStyle(fontSize: 18, color: Colors.grey)),
                    const SizedBox(height: 10),
                    Text(
                      _isMeasuring
                          ? '${_currentDb.toStringAsFixed(1)} dB'
                          : '--.- dB',
                      style: TextStyle(
                        fontSize: 60,
                        fontWeight: FontWeight.bold,
                        color: _currentDb > 70 ? Colors.redAccent : Colors.white,
                      ),
                    ),
                    Text(
                      _isMeasuring ? 'Midiendo... (5s)' : 'Presiona "Medir"',
                      style: const TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _isMeasuring ? null : _startMeasuring,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.teal.shade700,
                padding: const EdgeInsets.symmetric(vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30)),
              ),
              icon: Icon(_isMeasuring ? Icons.timer : Icons.mic),
              label: Text(
                _isMeasuring ? 'Midiendo... (5s)' : 'Medir y Guardar',
                style: const TextStyle(fontSize: 20),
              ),
            ),
            const SizedBox(height: 30),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade900,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.shade400),
              ),
              child: Row(
                children: [
                  const Icon(Icons.gps_fixed, color: Colors.tealAccent),
                  const SizedBox(width: 12),
                  Expanded(child: Text(_locationMessage)),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '🔊 Usando NoiseMeter para medir dB reales',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}


// 8. COMUNIDAD

class CommunityScreen extends StatelessWidget {
  const CommunityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    List<Map<String, String>> actividades = [
      {'usuario': 'Ana', 'lugar': 'Biblioteca Central', 'db': '45 dB'},
      {'usuario': 'Carlos', 'lugar': 'Parque Forestal', 'db': '32 dB'},
      {'usuario': 'María', 'lugar': 'Cafetería UTEM', 'db': '68 dB'},
      {'usuario': 'Pedro', 'lugar': 'Plaza de Armas', 'db': '78 dB'},
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Comunidad QuietZone'),
        backgroundColor: Colors.teal.shade900,
      ),
      body: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: actividades.length,
        itemBuilder: (context, index) {
          final item = actividades[index];
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: Colors.teal.shade700,
                child: Text(item['usuario']![0]),
              ),
              title: Text(item['usuario']!),
              subtitle: Text('📍 ${item['lugar']}'),
              trailing: Chip(
                label: Text(item['db']!),
                backgroundColor: Colors.teal.shade100,
                labelStyle: const TextStyle(color: Colors.black87),
              ),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          final parentState = context.findAncestorStateOfType<_HomeScreenState>();
          if (parentState != null) {
            parentState.setState(() => parentState._selectedIndex = 1);
          }
        },
        icon: const Icon(Icons.add),
        label: const Text('Aportar medición'),
        backgroundColor: Colors.teal.shade700,
      ),
    );
  }
}


// 9. AJUSTES
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes'),
        backgroundColor: Colors.teal.shade900,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSectionTitle('Privacidad'),
          _buildSwitchTile(
            title: 'Compartir ubicación exacta',
            subtitle: 'Permite que otros vean tu ubicación en el mapa',
            initialValue: true,
            onChanged: (val) {},
          ),
          _buildTile(
            title: 'Borrar datos locales',
            subtitle: 'Elimina todas las mediciones guardadas en tu teléfono',
            icon: Icons.delete_outline,
            onTap: () {},
          ),
          const Divider(height: 30),
          _buildSectionTitle('Medición'),
          _buildDropdownTile(
            title: 'Tiempo de grabación',
            value: '5 segundos',
            options: ['5 segundos', '10 segundos', '15 segundos'],
            onChanged: (val) {},
          ),
          _buildDropdownTile(
            title: 'Frecuencia de muestreo',
            value: 'Alta',
            options: ['Baja', 'Media', 'Alta'],
            onChanged: (val) {},
          ),
          const Divider(height: 30),
          _buildSectionTitle('Red'),
          _buildTile(
            title: 'URL del Backend',
            subtitle: 'http://localhost:8000 (Cambiar para pruebas)',
            icon: Icons.link,
            onTap: () {},
          ),
          _buildSwitchTile(
            title: 'Modo Offline',
            subtitle: 'Guarda datos localmente y sincroniza después',
            initialValue: false,
            onChanged: (val) {},
          ),
          const Divider(height: 30),
          _buildSectionTitle('Cuenta'),
          _buildTile(
            title: 'Mi historial',
            subtitle: 'Ver mis mediciones guardadas',
            icon: Icons.history,
            onTap: () {},
          ),
          _buildTile(
            title: 'Cerrar sesión',
            subtitle: 'Desconectar cuenta de Google',
            icon: Icons.logout,
            onTap: () async {
              await FirebaseAuth.instance.signOut();
              await GoogleSignIn().signOut();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sesión cerrada')),
                );
              }
            },
            textColor: Colors.redAccent,
          ),
          const Divider(height: 30),
          _buildSectionTitle('Soporte'),
          _buildTile(
            title: 'Enviar feedback',
            subtitle: 'Reporta errores o sugiere mejoras',
            icon: Icons.feedback,
            onTap: () {},
          ),
          _buildTile(
            title: 'Acerca de',
            subtitle: 'Versión 0.1.0 - Proyecto UTEM',
            icon: Icons.info_outline,
            onTap: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12.0),
    child: Text(title,
        style: TextStyle(
            color: Colors.tealAccent,
            fontSize: 16,
            fontWeight: FontWeight.bold)),
  );

  Widget _buildTile({required String title, required String subtitle,
    required IconData icon, required VoidCallback onTap, Color? textColor}) =>
      ListTile(
        leading: Icon(icon, color: Colors.grey),
        title: Text(title, style: TextStyle(color: textColor ?? Colors.white)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.grey),
        onTap: onTap,
      );

  Widget _buildSwitchTile({required String title, required String subtitle,
    required bool initialValue, required ValueChanged<bool> onChanged}) =>
      SwitchListTile(
        title: Text(title),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.grey)),
        value: initialValue,
        onChanged: onChanged,
        activeColor: Colors.tealAccent,
      );

  Widget _buildDropdownTile({required String title, required String value,
    required List<String> options, required ValueChanged<String?> onChanged}) =>
      ListTile(
        title: Text(title),
        subtitle: Text(value, style: const TextStyle(color: Colors.grey)),
        trailing: const Icon(Icons.arrow_drop_down, color: Colors.grey),
        onTap: () {},
      );
}

import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() {
  runApp(const AppRoot());
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});
  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  ThemeMode _themeMode = ThemeMode.light;
  String _currentThemeKey = 'sketch';
  bool _isLocked = true;
  String? _savedPassword;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentThemeKey = prefs.getString('theme_key') ?? 'sketch';
      _savedPassword = prefs.getString('app_password');
      if (_savedPassword == null || _savedPassword!.isEmpty) {
        _isLocked = false;
      }
    });
  }

  void _changeTheme(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_key', key);
    setState(() {
      _currentThemeKey = key;
    });
  }

  void _unlock() {
    setState(() { _isLocked = false; });
  }

  ThemeData getTheme(String key) {
    switch (key) {
      case 'dark':
        return ThemeData.dark().copyWith(
          scaffoldBackgroundColor: const Color(0xFF1A1A1A), 
          primaryColor: Colors.blueGrey[400],
          appBarTheme: AppBarTheme(backgroundColor: const Color(0xFF252525), foregroundColor: Colors.blueGrey[100]),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blueGrey[700], 
              foregroundColor: Colors.white
            )
          ),
          colorScheme: ColorScheme.dark(
            primary: Colors.blueGrey[400]!, 
            secondary: Colors.cyan[700]!
          ),
        );
      case 'matrix':
        return ThemeData.dark().copyWith(
          scaffoldBackgroundColor: Colors.black,
          primaryColor: Colors.green,
          appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Colors.green),
          elevatedButtonTheme: ElevatedButtonThemeData(style: ElevatedButton.styleFrom(backgroundColor: Colors.green[900], foregroundColor: Colors.greenAccent)),
          iconTheme: const IconThemeData(color: Colors.green),
          colorScheme: const ColorScheme.dark(primary: Colors.green, secondary: Colors.greenAccent),
          textTheme: const TextTheme(bodyMedium: TextStyle(color: Colors.green, fontFamily: 'monospace')),
        );
      case 'blue':
        return ThemeData.light().copyWith(
          primaryColor: Colors.blue,
          appBarTheme: const AppBarTheme(backgroundColor: Colors.blue, foregroundColor: Colors.white),
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        );
      case 'sketch':
      default:
        return ThemeData.light().copyWith(
          scaffoldBackgroundColor: const Color(0xFFF4F4F4),
          primaryColor: Colors.black,
          appBarTheme: const AppBarTheme(
            backgroundColor: Colors.white, 
            foregroundColor: Colors.black,
            elevation: 2,
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              side: const BorderSide(color: Colors.black, width: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))
            )
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: Colors.white,
            enabledBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.black, width: 2), borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(borderSide: const BorderSide(color: Colors.black, width: 3), borderRadius: BorderRadius.circular(8)),
          ),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLocked) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: getTheme(_currentThemeKey),
        home: LockScreen(savedPassword: _savedPassword!, onUnlock: _unlock),
      );
    }

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: getTheme(_currentThemeKey),
      home: SchoolBellApp(
        onThemeChanged: _changeTheme,
        currentTheme: _currentThemeKey,
      ),
    );
  }
}

class LockScreen extends StatefulWidget {
  final String savedPassword;
  final VoidCallback onUnlock;
  const LockScreen({super.key, required this.savedPassword, required this.onUnlock});

  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final TextEditingController _passController = TextEditingController();
  String error = "";

  void checkPass() {
    if (_passController.text == widget.savedPassword) {
      widget.onUnlock();
    } else {
      setState(() { error = "Неверный пароль"; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.lock, size: 80),
              const SizedBox(height: 20),
              const Text("Введите пароль", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
              const SizedBox(height: 20),
              TextField(
                controller: _passController,
                obscureText: true,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(border: OutlineInputBorder(), hintText: "****"),
              ),
              if (error.isNotEmpty) Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(error, style: const TextStyle(color: Colors.red)),
              ),
              const SizedBox(height: 20),
              ElevatedButton(onPressed: checkPass, child: const Text("ВОЙТИ", style: TextStyle(fontSize: 18))),
            ],
          ),
        ),
      ),
    );
  }
}

class SchoolBellApp extends StatefulWidget {
  final Function(String) onThemeChanged;
  final String currentTheme;
  const SchoolBellApp({super.key, required this.onThemeChanged, required this.currentTheme});

  @override
  State<SchoolBellApp> createState() => _SchoolBellAppState();
}

class _SchoolBellAppState extends State<SchoolBellApp> with SingleTickerProviderStateMixin {
  List<List<Map<String, String>>> schedule = List.generate(7, (_) => []);
  List<bool> daysActive = List.filled(7, true);
  bool isMuted = false;
  String espIp = "http://192.168.1.104"; 
  final String registryId = "are92cn6uf9uklct400n";
  final String registryPass = "n6aHX8v2_pnPSLD";
  final String deviceId = "are5meshq1nqv39p2633";
  String serverTime = "--:--:--";
  Timer? _timer;

  void _manageTemplates() async {
    final prefs = await SharedPreferences.getInstance();
    showModalBottomSheet(context: context, builder: (ctx) {
      return StatefulBuilder(builder: (context, setModalState) {
        Map<String, dynamic> templates = json.decode(prefs.getString('templates') ?? '{}');
        TextEditingController nameC = TextEditingController();

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Шаблоны расписания", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              TextField(controller: nameC, decoration: const InputDecoration(hintText: "Название (напр. 'Праздничное')")),
              ElevatedButton(onPressed: () async {
                if(nameC.text.isNotEmpty) {
                  templates[nameC.text] = schedule; 
                  await prefs.setString('templates', json.encode(templates));
                  setModalState((){});
                  showMsg("Сохранено!");
                }
              }, child: const Text("Сохранить текущее")),
              const Divider(),
              Expanded(
                child: ListView(
                  children: templates.keys.map((key) => ListTile(
                    title: Text(key),
                    trailing: IconButton(icon: const Icon(Icons.delete, color: Colors.red), onPressed: () async {
                      templates.remove(key); await prefs.setString('templates', json.encode(templates)); setModalState((){});
                    }),
                    onTap: () {
                      setState(() {
                        var raw = templates[key] as List;
                        schedule = List.generate(7, (i) => (raw[i] as List).map((l) => {"s": l['s'].toString(), "e": l['e'].toString()}).toList());
                      });
                      Navigator.pop(ctx);
                      showMsg("Загружено! Нажмите СОХРАНИТЬ.");
                    },
                  )).toList(),
                ),
              )
            ],
          ),
        );
      });
    });
  }

void _showWifiSettingsDialog() {
    TextEditingController ssidController = TextEditingController();
    TextEditingController passController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Настройка Wi-Fi"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("1. Подключитесь к SchoolBell_Setup\n2. Введи данные своего Wi-Fi:", style: TextStyle(fontSize: 12)),
            TextField(controller: ssidController, decoration: const InputDecoration(labelText: "Имя Wi-Fi (SSID)")),
            TextField(controller: passController, decoration: const InputDecoration(labelText: "Пароль"), obscureText: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Отмена")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(ctx);
              showMsg("Отправка настроек...");
              try {
                await http.post(Uri.parse('http://192.168.4.1/setwifi?ssid=${ssidController.text}&pass=${passController.text}'))
                    .timeout(const Duration(seconds: 5));
                showMsg("Готово! Плата перезагружается.");
              } catch (e) {
                showMsg("Ошибка! Вы подключены к SchoolBell_Setup?");
              }
            }, 
            child: const Text("СОХРАНИТЬ")
          ),
        ],
      ),
    );
  }
  late TabController _tabController;
  final List<String> daysLabels = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"];
  final List<String> daysFullNames = ["ПОНЕДЕЛЬНИК", "ВТОРНИК", "СРЕДА", "ЧЕТВЕРГ", "ПЯТНИЦА", "СУББОТА", "ВОСКРЕСЕНЬЕ"];
  int toadClicks = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _tabController.addListener(() { setState(() {}); });
    _loadSettings();
    
    _timer = Timer.periodic(const Duration(seconds: 2), (t) => _fetchTime());
  }

  @override
  void dispose() {
    _timer?.cancel(); 
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      espIp = prefs.getString('esp_ip') ?? "http://192.168.1.104";
    });
    loadData();
  }
  Future<void> _fetchTime() async {
    try {
      final res = await http.get(Uri.parse('$espIp/time')).timeout(const Duration(seconds: 2));
      if (res.statusCode == 200) {
        setState(() { 
          serverTime = res.body; 
        });
      }
    } catch (e) {
      setState(() { 
        serverTime = "Нет связи"; 
      });
    }
  }

  Future<void> _saveIp(String newIp) async {
    if (!newIp.startsWith("http")) newIp = "http://$newIp";
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('esp_ip', newIp);
    setState(() { espIp = newIp; });
    showMsg("IP сохранен");
    loadData();
  }

  Future<void> _savePassword(String newPass) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_password', newPass);
    showMsg(newPass.isEmpty ? "Пароль удален" : "Пароль установлен");
  }

  Future<void> loadData() async {
    try {
      final res = await http.get(Uri.parse('$espIp/data')).timeout(const Duration(seconds: 3));
      if (res.statusCode == 200) {
        final data = json.decode(res.body);
        setState(() {
          schedule = List.generate(7, (i) {
            return (data['schedule'][i] as List).map((l) => {
              "s": l['s'].toString(),
              "e": l['e'].toString()
            }).toList();
          });
          daysActive = List<bool>.from(data['days']);
          isMuted = data['mute'] ?? false;
        });
      }
    } catch (e) {
      
    }
  }

Future<void> triggerHybridBell() async {
    showMsg("Отправка команды...");
    try {
      final res = await http.post(Uri.parse('$espIp/manual')).timeout(const Duration(seconds: 1));
      if (res.statusCode == 200) { showMsg("🔔 Звонок (Локально)"); return; }
    } catch (e) {
      try {
        final client = MqttServerClient.withPort('mqtt.cloud.yandex.net', 'flutter_client', 8883);
        client.secure = true;
        client.connectionMessage = MqttConnectMessage().authenticateAs(registryId, registryPass);
        await client.connect().timeout(const Duration(seconds: 3));
        
        final builder = MqttClientPayloadBuilder();
        builder.addString('RING');
        client.publishMessage('\$devices/$deviceId/commands/ring', MqttQos.atLeastOnce, builder.payload!);
        client.disconnect();
        showMsg("🔔 Звонок (Через Облако)");
      } catch (e) {
        showMsg("Нет связи с платой");
      }
    }
  }
  Future<void> saveData() async {
    try {
      await http.post(
        Uri.parse('$espIp/save'),
        body: json.encode({ "schedule": schedule, "days": daysActive, "mute": isMuted })
      );
      showMsg("СОХРАНЕНО!");
    } catch (e) {
      showMsg("Ошибка сохранения");
    }
  }

  Future<void> _resetDevice() async {
    bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Сброс настроек"),
        content: const Text("Вы уверены, что хотите полностью сбросить настройки и Wi-Fi? Плата будет очищена и перезагрузится."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Отмена")),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true), 
            child: const Text("Сбросить", style: TextStyle(color: Colors.red))
          ),
        ],
      ),
    );

    if (confirmed == true) {
      showMsg("Сигнал сброса отправлен...");
      await sendCommand('/reset');
    }
  }

  Future<void> sendCommand(String path) async {
    try { await http.post(Uri.parse('$espIp$path')).timeout(const Duration(seconds: 3)); } catch (e) { showMsg("Ошибка связи"); }
  }

  void showMsg(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));
  }

  void addLesson() { setState(() { schedule[_tabController.index].add({"s": "", "e": ""}); }); }
  void removeLesson(int index) { setState(() { schedule[_tabController.index].removeAt(index); }); }

  void copyToAll() {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      title: const Text("Скопировать?"),
      content: Text("Расписание '${daysFullNames[_tabController.index]}' будет везде."),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Нет")),
        TextButton(onPressed: () {
          setState(() {
            final currentDay = schedule[_tabController.index];
            for (int i = 0; i < 7; i++) {
              schedule[i] = List.from(currentDay.map((e) => Map<String, String>.from(e)));
            }
          });
          Navigator.pop(ctx);
          showMsg("Скопировано!");
        }, child: const Text("Да")),
      ],
    ));
  }

  void _showIpDialog() {
    TextEditingController ipController = TextEditingController(text: espIp.replaceAll("http://", ""));
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("Настройка IP платы"),
      content: TextField(controller: ipController, decoration: const InputDecoration(labelText: "Например 192.168.1.104")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("Отмена")),
        TextButton(onPressed: () { _saveIp(ipController.text); Navigator.pop(c); }, child: const Text("OK")),
      ],
    ));
  }

  void _showPassDialog() {
    TextEditingController passController = TextEditingController();
    showDialog(context: context, builder: (c) => AlertDialog(
      title: const Text("Установить пароль"),
      content: TextField(controller: passController, decoration: const InputDecoration(labelText: "Новый пароль (пусто = без пароля)")),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: const Text("Отмена")),
        TextButton(onPressed: () { _savePassword(passController.text); Navigator.pop(c); }, child: const Text("OK")),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    bool isSketch = widget.currentTheme == 'sketch';
    Color mainColor = Theme.of(context).primaryColor;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(daysFullNames[_tabController.index], 
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            Text(serverTime, 
                  style: TextStyle(fontSize: 13, color: Colors.blueGrey[300], fontWeight: FontWeight.w400)), 
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.bookmarks), onPressed: _manageTemplates),
        ],
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          tabs: daysLabels.map((d) => Tab(text: d)).toList(),
        ),
      ),
      
      drawer: Drawer(
        width: 320,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const SizedBox(height: 40),
                        ListTile(
              leading: const Icon(Icons.router, color: Colors.blue),
              title: const Text("Настроить Wi-Fi"),
              subtitle: const Text("Ввод логина/пароля"),
              onTap: _showWifiSettingsDialog, 
            ),
            const Divider(),
            
            ListTile(
              leading: Icon(Icons.wifi, color: mainColor),
              title: const Text("Настроить IP"),
              subtitle: Text(espIp),
              onTap: _showIpDialog,
              shape: isSketch ? RoundedRectangleBorder(side: BorderSide(color: mainColor), borderRadius: BorderRadius.circular(5)) : null,
            ),
            const SizedBox(height: 10),
            ListTile(
              leading: Icon(Icons.security, color: mainColor),
              title: const Text("Пароль приложения"),
              onTap: _showPassDialog,
              shape: isSketch ? RoundedRectangleBorder(side: BorderSide(color: mainColor), borderRadius: BorderRadius.circular(5)) : null,
            ),
            
            const Divider(),
            
            const Text("Тема оформления:", style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 10,
              children: [
                _themeBtn("Светлая", "sketch"),
                _themeBtn("Темная", "dark"),
                _themeBtn("Матрица", "matrix"),
                _themeBtn("Синяя", "blue"),
              ],
            ),

            const Divider(),

            const Text("Активные дни:", style: TextStyle(fontWeight: FontWeight.bold)),
            Wrap(
              spacing: 5,
              children: List.generate(7, (i) => FilterChip(
                label: Text(daysLabels[i]), 
                selected: daysActive[i],
                onSelected: (v) => setState(() => daysActive[i] = v),
              )),
            ),
            
            const Divider(),
            
                        const Text("Настройка часов:", style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8, runSpacing: 8, 
              alignment: WrapAlignment.center, 
              children: [
                _adjustBtn("+ Ч", "h", 1), _adjustBtn("+ М", "m", 1),
                _adjustBtn("- Ч", "h", -1), _adjustBtn("- М", "m", -1),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10, runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                _dateBtn("+ Д", "d", 1), _dateBtn("+ Мес", "mo", 1),
                _dateBtn("- Д", "d", -1), _dateBtn("- Мес", "mo", -1),
              ],
            ),

            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: isMuted ? Colors.grey : Colors.orange,
                foregroundColor: Colors.white,
              ),
              onPressed: () { setState(() => isMuted = !isMuted); saveData(); },
              child: Text(isMuted ? "🔕 ЗВОНКИ ВЫКЛЮЧЕНЫ" : "🔔 ЗВОНКИ ВКЛЮЧЕНЫ"),
            ),

            const SizedBox(height: 30),
            GestureDetector(
              onTap: () {
                toadClicks++;
                if(toadClicks >= 5) { showMsg("Андрей гриб🍄"); toadClicks=0; }
              },
              child: const Center(child: Text("🐸", style: TextStyle(fontSize: 50))),
            )
          ],
        ),
      ),

      body: TabBarView(
        controller: _tabController,
        children: List.generate(7, (dayIdx) {
          return Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
                Expanded(
                  child: Card(
                    elevation: isSketch ? 0 : 2,
                    shape: isSketch ? RoundedRectangleBorder(side: BorderSide(color: mainColor, width: 2), borderRadius: BorderRadius.circular(10)) : null,
                    color: isSketch ? Colors.white : null,
                    child: ListView.separated(
                      padding: const EdgeInsets.all(15),
                      itemCount: schedule[dayIdx].length,
                      separatorBuilder: (c,i) => const SizedBox(height: 10),
                      itemBuilder: (ctx, i) {
                        return Row(
                          children: [
                            SizedBox(width: 20, child: Text("${i + 1}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16))),
                            Expanded(child: _timeInput(dayIdx, i, "s", "НАЧ")),
                            const SizedBox(width: 10),
                            Expanded(child: _timeInput(dayIdx, i, "e", "КОН")),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.red),
                              onPressed: () => removeLesson(i),
                            )
                          ],
                        );
                      },
                    ),
                  ),
                ),
                
                const SizedBox(height: 10),
                
                Row(
                  children: [
                    Expanded(child: ElevatedButton(onPressed: addLesson, child: const Icon(Icons.add))),
                    const SizedBox(width: 10),
                    Expanded(child: ElevatedButton(onPressed: copyToAll, child: const Icon(Icons.copy))),
                  ],
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, padding: const EdgeInsets.all(15)),
                    onPressed: saveData,
                    child: const Text("СОХРАНИТЬ", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white, padding: const EdgeInsets.all(15)),
                    onPressed: triggerHybridBell,
                    child: const Text("🔔 РУЧНОЙ ЗВОНОК", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                )
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _timeInput(int d, int i, String key, String label) {
    bool isSketch = widget.currentTheme == 'sketch';
    return TextFormField(
      initialValue: schedule[d][i][key],
      keyboardType: TextInputType.datetime,
      textAlign: TextAlign.center,
      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
      decoration: InputDecoration(
        labelText: label,
        contentPadding: const EdgeInsets.symmetric(vertical: 5, horizontal: 5),
        border: isSketch ? const OutlineInputBorder() : null,
      ),
      onChanged: (val) {
        String newVal = val.replaceAll(RegExp(r'[.,;]'), ':');
        schedule[d][i][key] = newVal;
      },
    );
  }

  Widget _adjustBtn(String txt, String type, int val) {
    return SizedBox(
      width: 60, height: 40,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
        onPressed: () => sendCommand('/adjust?type=$type&val=$val'),
        child: Text(txt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
      ),
    );
  }
  
  Widget _dateBtn(String txt, String type, int val) {
    return SizedBox(
      width: 60, height: 40,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(padding: EdgeInsets.zero),
        onPressed: () => sendCommand('/adjustDate?type=$type&val=$val'),
        child: Text(txt, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
      ),
    );
  }

  Widget _themeBtn(String name, String key) {
    return ActionChip(
      label: Text(name),
      backgroundColor: widget.currentTheme == key ? Theme.of(context).primaryColor : null,
      labelStyle: TextStyle(color: widget.currentTheme == key ? Colors.white : null),
      onPressed: () => widget.onThemeChanged(key),
    );
  }
}
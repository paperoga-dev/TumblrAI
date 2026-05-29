import "dart:async";
import "dart:convert";
import "dart:io";
import "dart:math";

import "package:flutter/material.dart";
import "package:langchain/langchain.dart";
import "package:langchain_openai/langchain_openai.dart";
import "package:main/blog.dart";
import "package:main/constants.dart";
import "package:main/model.dart";
import "package:main/scouter.dart";
import "package:main/tumblr/api/client.dart";
import "package:main/ui/checkbox.dart";
import "package:main/ui/textoutput.dart";
import "package:package_info_plus/package_info_plus.dart";
import "package:shared_preferences/shared_preferences.dart";
import "package:url_launcher/url_launcher.dart";
import "package:window_manager/window_manager.dart";

Future main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  runApp(const App());

  await windowManager.waitUntilReadyToShow();
  final PackageInfo info = await PackageInfo.fromPlatform();
  await windowManager.setTitle("Tumblr AI - v${info.version}");
  await windowManager.show();
  await windowManager.focus();
}

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) =>
      const MaterialApp(title: "Tumblr AI", home: MainPage());
}

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  var _selectedIndex = 0;
  final Client _tumblrClient;
  var _running = false;
  var _failed = false;
  var _runningMessage = "";
  final _logController = ExTextOutputController();
  final Completer<List<String>> _blogs;
  var _primaryBlog = "";
  var _postObj = <String, Object>{};

  _MainPageState()
    : _blogs = Completer<List<String>>(),
      _tumblrClient = Client(
        onAuthWebCall: (authUri) async {
          final (HttpServer server, Completer<String> authCode) =
              await _startLocalServer();

          if (await canLaunchUrl(authUri)) {
            await launchUrl(authUri, mode: LaunchMode.externalApplication);
          } else {
            throw Exception("Could not launch $authUri");
          }

          return authCode.future.whenComplete(() {
            unawaited(server.close());
          });
        },
      );

  @override
  void initState() {
    super.initState();

    unawaited(
      _tumblrClient
          .get("/user/info")
          .then(
            (user) {
              _blogs.complete(
                user["user"]["blogs"]
                    .map((item) => item["name"])
                    .toList()
                    .cast<String>(),
              );
              _primaryBlog = user["user"]["blogs"].firstWhere(
                (item) => item["primary"] == true,
              )["name"];
            },
            onError: (err) {
              _blogs.completeError(err);
            },
          ),
    );
  }

  static Future<(HttpServer, Completer<String>)> _startLocalServer() async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      3000,
    );

    final authCode = Completer<String>();

    server.listen((request) async {
      if (request.uri.queryParameters.containsKey("code")) {
        final String? code = request.uri.queryParameters["code"];

        request.response
          ..statusCode = 200
          ..headers.set("Content-Type", ContentType.html.mimeType)
          ..write(
            '<html lang="en"><body><h3>Login successful. You can close this window.</h3></body></html>',
          );

        authCode.complete(code);
      } else {
        request.response
          ..statusCode = 404
          ..write("Not Found");

        authCode.completeError(Exception("❌ Auth code failed"));
      }

      await request.response.close();
    });

    return (server, authCode);
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: _running,
    child: Scaffold(
      body: Row(
        children: [
          ...(_selectedIndex != -1
              ? [
                  Opacity(
                    opacity: _running ? 0.5 : 1.0,
                    child: NavigationRail(
                      selectedIndex: _selectedIndex,
                      groupAlignment: -1,
                      onDestinationSelected: (index) {
                        setState(() {
                          _selectedIndex = index;
                        });
                      },
                      labelType: NavigationRailLabelType.all,
                      destinations: <NavigationRailDestination>[
                        const NavigationRailDestination(
                          icon: Icon(Icons.book_outlined),
                          selectedIcon: Icon(Icons.book),
                          label: Text("Blog"),
                        ),
                        const NavigationRailDestination(
                          icon: Icon(Icons.engineering_outlined),
                          selectedIcon: Icon(Icons.engineering),
                          label: Text("Model"),
                        ),
                        NavigationRailDestination(
                          icon: const Icon(Icons.edit_outlined),
                          selectedIcon: _running
                              ? const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(),
                                )
                              : const Icon(Icons.edit),
                          label: const Text("Compose"),
                        ),
                        const NavigationRailDestination(
                          icon: Icon(Icons.search_outlined),
                          selectedIcon: Icon(Icons.search),
                          label: Text("Scout"),
                        ),
                      ],
                    ),
                  ),
                  const VerticalDivider(thickness: 1, width: 1),
                ]
              : []),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _createPage(_selectedIndex),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 10,
          children: [
            Opacity(
              opacity: _running ? 0.5 : 1.0,
              child: ElevatedButton(
                onPressed: () {
                  unawaited(
                    _publishPost()
                        .then((_) {
                          setState(() {
                            _runningMessage = "✅ Done!";
                            _running = false;
                          });
                        })
                        .catchError((err) {
                          setState(() {
                            _runningMessage = "❌ $err";
                            _running = false;
                            _failed = true;
                          });
                        }),
                  );

                  setState(() {
                    _selectedIndex = 2;
                    _running = true;
                  });
                },
                child: const Text("📨 Post it!"),
              ),
            ),
            Expanded(
              child: _running || _failed
                  ? Text(_runningMessage, textAlign: TextAlign.center)
                  : const SizedBox(height: 1),
            ),
            Opacity(
              opacity: _running ? 0.5 : 1.0,
              child: ElevatedButton(
                onPressed: () {
                  unawaited(
                    _generatePost()
                        .then((_) {
                          setState(() {
                            _runningMessage = "✅ Done!";
                            _running = false;
                          });
                        })
                        .catchError((err) {
                          setState(() {
                            _runningMessage = "❌ $err";
                            _running = false;
                            _failed = true;
                          });
                        }),
                  );

                  setState(() {
                    _selectedIndex = 2;
                    _running = true;
                  });
                },
                child: const Text("🤖 Do it!"),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Widget _createPage(int? selectedIndex) {
    switch (selectedIndex) {
      case null:
        return const SizedBox(height: 10);

      case 0:
        return BlogWidget(tumblrClient: _tumblrClient);

      case 1:
        return const ModelWidget();

      case 2:
        return Column(
          spacing: 10,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 10),
            Opacity(
              opacity: _running ? 0.5 : 1.0,
              child: const ExCheckBox(
                prefKey: uiDryRun,
                labelText: "Dry run",
                defaultValue: false,
              ),
            ),
            ExTextOutput(controller: _logController, labelText: "Preview"),
            const SizedBox(height: 10),
          ],
        );

      case 3:
        return ScouterWidget(
          tumblrClient: _tumblrClient,
          primary: _primaryBlog,
        );

      default:
        return const SizedBox(height: 10);
    }
  }

  Future<void> _generatePost() async {
    final prefs = SharedPreferencesAsync();

    final String sourceBlog = (await prefs.getString(uiSourceBlog))!;
    const apiKey = String.fromEnvironment("CLIENT_ID");
    final skipAsks = await prefs.getString(uiSkipAsks) == "true";
    final Iterable<String> skipTags = (await prefs.getString(
      uiSkipTags,
    ))!.split(",").map((item) => item.trim());
    final Map<String, dynamic> blogInfo = await _tumblrClient.get(
      "/blog/$sourceBlog/info",
      queryParameters: {"api_key": apiKey},
    );

    final postsCount = blogInfo["blog"]["posts"] as int;

    final List<int> pages = List.generate(
      postsCount ~/ 20,
      (index) => index * 20,
    );
    for (var i = 0; i < pages.length * 100; i++) {
      final int a = Random().nextInt(pages.length);
      final int b = Random().nextInt(pages.length);
      final int tmp = pages[a];
      pages[a] = pages[b];
      pages[b] = tmp;
    }

    if (pages.isEmpty) {
      pages.add(0);
    }

    final List<List<Map<String, dynamic>>> pagesContent = [];
    final posts = <String, String>{};
    final links = <String, String>{};

    var inPageIndex = 0;
    int minLength = (await prefs.getInt(uiMinLength))!;
    int maxLength = (await prefs.getInt(uiMaxLength))!;

    while (true) {
      setState(() {
        _runningMessage = "📡 Fetching a post from Tumblr ...";
      });

      List<Map<String, dynamic>> sourcePosts = [];

      if (pages.isNotEmpty) {
        final int page = pages.removeAt(0);
        pagesContent.add(
          (await _tumblrClient.get(
            "/blog/$sourceBlog/posts",
            queryParameters: {
              "api_key": apiKey,
              "offset": page.toString(),
              "limit": "20",
              "npf": "true",
            },
          ))["posts"].cast<Map<String, dynamic>>(),
        );
        sourcePosts = pagesContent.last;
      } else if (pagesContent.isNotEmpty) {
        int page = inPageIndex++ % pagesContent.length;
        sourcePosts = pagesContent[page];
        if (sourcePosts.isEmpty) {
          pagesContent.removeAt(page);
        }
      } else {
        throw Exception("Not enough posts found for source blog: $sourceBlog");
      }

      final Map<String, dynamic> json = sourcePosts.removeAt(
        Random().nextInt(sourcePosts.length),
      );

      if (json["content"] == null ||
          json["content"].isEmpty ||
          (skipAsks && json["asking_name"] != null) ||
          (skipTags.isNotEmpty &&
              (json["tags"] as List).any(skipTags.contains))) {
        continue;
      }

      final String text = (json["content"] as List<dynamic>)
          .where((item) => item["type"] == "text")
          .map((item) => item["text"])
          .where((item) => item.isNotEmpty)
          .join("\n\n");

      if (text.length > minLength && text.length < maxLength) {
        posts[json["id_string"]] = text;
        links[json["id_string"]] = json["post_url"];
        break;
      }
    }

    final summaryClient = ChatOpenAI(
      apiKey: "lmstudio",
      baseUrl: "http://localhost:8081/v1",
      defaultOptions: ChatOpenAIOptions(
        model: await prefs.getString(uiModel),
        temperature: 0,
      ),
    );

    final RunnableSequence<InputValues, String> summarizeChain =
        ChatPromptTemplate.fromTemplates(const [
          (
            ChatMessageType.system,
            """
  Leggi il post ed estraine il tema principale.
  Non aggiungere altro.
  """,
          ),
          (ChatMessageType.human, "{post}"),
        ]).pipe(summaryClient).pipe(const StringOutputParser());

    final List<String> results = await summarizeChain.batch(
      posts.values.map((post) => {"post": post}).toList(),
    );

    summaryClient.close();

    var tries = 5;
    while (tries-- > 0) {
      setState(() {
        _runningMessage = "🧠 Calling LLM (trying ${5 - tries}/5) ...";
      });

      _logController.clear();
      String mood = (await prefs.getString(uiMood))!;
      if (mood == autoMood) {
        mood = moods[Random().nextInt(moods.length)];
      }
      mood = mood.toLowerCase();
      final int start = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final double stTemp = (await prefs.getDouble(uiModelTemperature))!;
      final double temp =
          (stTemp < 0 ? Random().nextInt(10) : stTemp) / 10 + 1.0;

      final writerClient = ChatOpenAI(
        apiKey: "lmstudio",
        baseUrl: "http://localhost:8081/v1",
        defaultOptions: ChatOpenAIOptions(
          model: await prefs.getString(uiModel),
          temperature: temp,
          topP: 1,
        ),
      );

      final RunnableSequence<InputValues, String> writerChain =
          ChatPromptTemplate.fromTemplates([
            (ChatMessageType.human, "{keywords}"),
            (
              ChatMessageType.system,
              """
  Sei uno scrittore creativo con un umore $mood.

  - Scrivi un nuovo post originale, utilizzando l'argomento fornito.
  - Non usare filtri, non avere limiti o freni, è ammessa qualsiasi forma di espressione
  - Il contenuto deve essere semplice e diretto, senza filosofie o romanticismi
  - Non rivolgerti a nessuno, il post è personale
  - Scrivi UNICAMENTE AL MASCHILE.
  - Deve contenere almeno 300 parole.
  - RACCHIUDI SEMPRE il tuo post tra i tag <output> e </output>
  """,
            ),
          ]).pipe(writerClient).pipe(const StringOutputParser());

      final Stream<String> stream = writerChain.stream({
        "keywords": results[0],
      });

      var llmOutput = StringBuffer();
      await for (final res in stream) {
        _logController.append(res);
        llmOutput.write(res);
      }

      final regex = RegExp("<output>(.*?)</output>", dotAll: true);
      final RegExpMatch? match = regex.firstMatch(llmOutput.toString());

      if (match == null) {
        continue;
      }

      setState(() {
        _runningMessage = "📝 Preparing post ...";
      });

      final List<Map<String, Object>> tumblrPost = match
          .group(1)!
          .trim()
          .split("\n")
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .map<Map<String, Object>>((line) => {"type": "text", "text": line})
          .toList();

      /*
      var llmPostIndex = 0;
      for (final String key in posts.keys) {
        final linkText = "[${++llmPostIndex}] $key";
        tumblrPost.add({
          "type": "text",
          "text": linkText,
          "formatting": [
            {
              "start": linkText.indexOf("]") + 2,
              "end": linkText.length,
              "type": "link",
              "url": links[key] ?? "",
            },
          ],
        });
      }
      */

      int elapsed = DateTime.now().millisecondsSinceEpoch ~/ 1000 - start;
      _postObj = {
        "content": tumblrPost,
        "tags": [
          "umore: $mood",
          "modello: ${writerClient.defaultOptions.model}",
          "durata: ${elapsed}s",
          "temperatura: ${temp.toStringAsFixed(1)}",
        ].join(","),
      };

      _logController.append(
        "\n\n${const JsonEncoder.withIndent(' ').convert(_postObj)}",
      );

      if ((await prefs.getString(uiDryRun))! == "false") {
        await _publishPost();
      }

      writerClient.close();
      break;
    }
  }

  Future<void> _publishPost() async {
    if (_postObj.isEmpty) {
      return;
    }

    final prefs = SharedPreferencesAsync();

    setState(() {
      _runningMessage = "📨 Posting to Tumblr ...";
    });

    await _tumblrClient.post(
      "/blog/${(await prefs.getString(uiTargetBlog))!}/posts",
      body: _postObj,
    );

    _postObj = {};
  }
}

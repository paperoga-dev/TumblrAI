import "dart:async";

import "package:flutter/material.dart";
import "package:main/constants.dart";
import "package:main/ui/listview.dart";
import "package:main/ui/slider.dart";
import "package:openai_dart/openai_dart.dart";

class ModelWidget extends StatefulWidget {
  const ModelWidget({super.key});

  @override
  State<ModelWidget> createState() => _ModelWidgetState();
}

class _ModelWidgetState extends State<ModelWidget> {
  final Completer<List<String>> _models;

  _ModelWidgetState() : _models = Completer<List<String>>();

  @override
  void initState() {
    super.initState();

    unawaited(
      OpenAIClient(
        apiKey: "",
        baseUrl: "http://localhost:1234/v1",
      ).listModels().then(
        (modelsResp) {
          _models.complete(modelsResp.data.map((item) => item.id).toList());
        },
        onError: (err) {
          _models.completeError(err);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      const SizedBox(height: 30),
      Expanded(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          spacing: 10,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 10,
                children: [
                  Expanded(
                    child: ExListView(
                      prefKey: uiModel,
                      labelText: "Model:",
                      items: _models.future,
                      defaultValue: "",
                      waitingMessage: "👾 Contacting Ollama ...",
                    ),
                  ),
                  const ExSlider(
                    labelText: "Temperature:",
                    prefKey: uiModelTemperature,
                  ),
                  const ExSlider(labelText: "Top_P:", prefKey: uiModelTopP),
                ],
              ),
            ),
            Expanded(
              child: ExListView(
                items: Future<List<String>>.value([autoMood, ...moods]),
                labelText: "Mood:",
                prefKey: uiMood,
                defaultValue: autoMood,
                waitingMessage: "",
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 30),
    ],
  );
}

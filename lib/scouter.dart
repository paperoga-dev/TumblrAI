import "dart:async";

import "package:flutter/material.dart";
import "package:main/tumblr/api/client.dart";

class ScouterWidget extends StatefulWidget {
  final Client tumblrClient;
  final String primary;

  const ScouterWidget({
    super.key,
    required this.tumblrClient,
    required this.primary,
  });

  @override
  State<ScouterWidget> createState() => _ScouterWidgetState();
}

class _ScouterWidgetState extends State<ScouterWidget> {
  final Completer<List<String>> _blogs;

  _ScouterWidgetState() : _blogs = Completer<List<String>>();

  @override
  void initState() {
    super.initState();

    final List<String> blogs = [];
    final double now = DateTime.now().millisecondsSinceEpoch / 1000;

    unawaited(
      widget.tumblrClient
          .get("/blog/${widget.primary}/followers")
          .then(
            (users) {
              blogs.addAll(
                users["users"]
                    .where(
                      (item) =>
                          item["following"] == false &&
                          (now - item["updated"]) < (86400 * 30),
                    )
                    .map((item) => item["name"])
                    .toList()
                    .cast<String>(),
              );

              blogs.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
              _blogs.complete(blogs);
            },
            onError: (err) {
              _blogs.completeError(err);
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<List<String>>(
    future: _blogs.future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: Text("Aspe'"));
      } else {
        if (snapshot.hasError) {
          return Center(child: Text("❌ Error: ${snapshot.error}"));
        } else {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Seeee"),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: snapshot.data!.length,
                  itemBuilder: (context, index) => ListTile(
                    title: Text(
                      snapshot.data![index],
                      style: const TextStyle(color: Colors.black),
                    ),
                  ),
                ),
              ),
            ],
          );
        }
      }
    },
  );
}

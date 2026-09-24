import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    print(e);
  }
  runApp(const MaterialApp(home: RanaCameraHome()));
}

class RanaCameraHome extends StatefulWidget {
  const RanaCameraHome({super.key});

  @override
  State<RanaCameraHome> createState() => _RanaCameraHomeState();
}

class _RanaCameraHomeState extends State<RanaCameraHome> {
  CameraController? controller;
  bool isProcessing = false;
  File? processedImage;

  final String apiUrl = "https://violet-animals-float.loca.lt/process-portrait/";

  @override
  void initState() {
    super.initState();
    if (cameras.isNotEmpty) {
      controller = CameraController(cameras[0], ResolutionPreset.max);
      controller!.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
      });
    }
  }

  Future<void> takeAndProcessPhoto() async {
    if (controller == null || !controller!.value.isInitialized || isProcessing) return;

    setState(() => isProcessing = true);

    try {
      final image = await controller!.takePicture();
      var request = http.MultipartRequest('POST', Uri.parse(apiUrl));
      request.files.add(await http.MultipartFile.fromPath('file', image.path));
      var response = await request.send();

      if (response.statusCode == 200) {
        var bytes = await response.stream.toBytes();
        final dir = await getTemporaryDirectory();
        File file = File('${dir.path}/enhanced.jpg');
        await file.writeAsBytes(bytes);

        setState(() {
          processedImage = file;
          isProcessing = false;
        });
      } else {
        setState(() => isProcessing = false);
      }
    } catch (e) {
      setState(() => isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (processedImage != null)
            Image.file(processedImage!, fit: BoxFit.cover, width: double.infinity, height: double.infinity)
          else if (controller != null && controller!.value.isInitialized)
            CameraPreview(controller!)
          else
            const Center(child: CircularProgressIndicator()),

          if (isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.amber),
                    SizedBox(height: 15),
                    Text("AI Processing Portrait...", style: TextStyle(color: Colors.white, fontSize: 16))
                  ],
                ),
              ),
            ),

          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: FloatingActionButton.large(
                backgroundColor: Colors.white,
                onPressed: takeAndProcessPhoto,
                child: const Icon(Icons.camera, color: Colors.black, size: 40),
              ),
            ),
          )
        ],
      ),
    );
  }
}

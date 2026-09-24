import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:image_gallery_saver/image_gallery_saver.dart';
import 'package:permission_handler/permission_handler.dart';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    cameras = await availableCameras();
  } catch (e) {
    print(e);
  }
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: RanaCameraHome(),
  ));
}

class RanaCameraHome extends StatefulWidget {
  const RanaCameraHome({super.key});

  @override
  State<RanaCameraHome> createState() => _RanaCameraHomeState();
}

class _RanaCameraHomeState extends State<RanaCameraHome> {
  CameraController? controller;
  bool isProcessing = false;
  double processPercentage = 0.0;
  String statusMessage = "";
  Uint8List? processedBytes;
  final ImagePicker _picker = ImagePicker();

  // Hugging Face Direct API Endpoint
  final String apiUrl = "https://hellowaminul-rana-portrait-api.hf.space/process-portrait/";

  @override
  void initState() {
    super.initState();
    initCamera();
    requestPermissions();
  }

  Future<void> initCamera() async {
    if (cameras.isNotEmpty) {
      controller = CameraController(
        cameras[0],
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller!.initialize();
      await controller!.setFlashMode(FlashMode.off);
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> requestPermissions() async {
    await Permission.storage.request();
    await Permission.photos.request();
  }

  void updateProgress(double percent, String msg) {
    setState(() {
      processPercentage = percent;
      statusMessage = msg;
    });
  }

  Future<void> pickFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      processImageFile(File(image.path));
    }
  }

  Future<void> takePhoto() async {
    if (controller == null || !controller!.value.isInitialized || isProcessing) return;

    try {
      await controller!.setFlashMode(FlashMode.off);
      final image = await controller!.takePicture();
      processImageFile(File(image.path));
    } catch (e) {
      showDialogMsg("Error", "ক্যামেরা থেকে ছবি তুলতে সমস্যা হয়েছে: $e");
    }
  }

  Future<void> processImageFile(File rawImageFile) async {
    setState(() {
      isProcessing = true;
      processedBytes = null;
      processPercentage = 0.05;
      statusMessage = "ছবি প্রস্তুত করা হচ্ছে...";
    });

    try {
      updateProgress(0.15, "সার্ভারে কানেক্ট করা হচ্ছে...");
      
      var uri = Uri.parse(apiUrl);
      var request = http.MultipartRequest('POST', uri);
      
      var fileStream = http.ByteStream(rawImageFile.openRead());
      var length = await rawImageFile.length();

      var multipartFile = http.MultipartFile(
        'file',
        fileStream,
        length,
        filename: rawImageFile.path.split('/').last,
      );

      request.files.add(multipartFile);

      updateProgress(0.35, "ছবি আপলোড হচ্ছে (৩৫%)...");

      var streamedResponse = await request.send().timeout(const Duration(seconds: 90));
      
      updateProgress(0.65, "AI পোর্ট্রেট প্রসেসিং হচ্ছে (৬৫%)...");

      if (streamedResponse.statusCode == 200) {
        updateProgress(0.85, "প্রসেসড ছবি ডাউনলোড হচ্ছে (৮৫%)...");
        
        List<int> bytesList = [];
        int totalReceived = 0;
        int? contentLength = streamedResponse.contentLength;

        await for (var chunk in streamedResponse.stream) {
          bytesList.addAll(chunk);
          totalReceived += chunk.length;
          if (contentLength != null && contentLength > 0) {
            double downloadProgress = 0.85 + ((totalReceived / contentLength) * 0.10);
            updateProgress(downloadProgress, "ডাউনলোড হচ্ছে ${(downloadProgress * 100).toInt()}%...");
          }
        }

        Uint8List imageBytes = Uint8List.fromList(bytesList);

        updateProgress(0.95, "গ্যালারিতে সেভ করা হচ্ছে...");

        await ImageGallerySaver.saveImage(
          imageBytes,
          quality: 100,
          name: "AI_Portrait_${DateTime.now().millisecondsSinceEpoch}",
        );

        updateProgress(1.0, "সম্পন্ন হয়েছে!");

        setState(() {
          processedBytes = imageBytes;
          isProcessing = false;
        });

        showDialogMsg("Success", "ছবিটি সফলভাবে প্রসেসড হয়েছে এবং গ্যালারিতে সেভ করা হয়েছে!");
      } else {
        setState(() => isProcessing = false);
        showDialogMsg("Server Failure", "সার্ভার এরর (Code: ${streamedResponse.statusCode})। Hugging Face Space চালু আছে কিনা চেক করুন।");
      }
    } catch (e) {
      setState(() => isProcessing = false);
      showDialogMsg("Connection Error", "সমস্যা: $e\nইন্টারনেট কানেকশন বা URL চেক করুন।");
    }
  }

  void showDialogMsg(String title, String message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text("OK"),
          )
        ],
      ),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          if (processedBytes != null)
            Positioned.fill(
              child: Image.memory(processedBytes!, fit: BoxFit.contain),
            )
          else if (controller != null && controller!.value.isInitialized)
            Center(
              child: CameraPreview(controller!),
            )
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          if (isProcessing)
            Container(
              color: Colors.black87,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(25),
                  margin: const EdgeInsets.symmetric(horizontal: 30),
                  decoration: BoxDecoration(
                    color: Colors.grey[900],
                    borderRadius: BorderRadius.circular(15),
                    border: Border.all(color: Colors.amber, width: 1.5),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(
                        value: processPercentage > 0 ? processPercentage : null,
                        color: Colors.amber,
                        strokeWidth: 6,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        "${(processPercentage * 100).toInt()}%",
                        style: const TextStyle(color: Colors.amber, fontSize: 28, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        statusMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),

          if (processedBytes != null && !isProcessing)
            Positioned(
              top: 50,
              left: 20,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      processedBytes = null;
                    });
                  },
                ),
              ),
            ),

          if (processedBytes == null && !isProcessing)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  FloatingActionButton(
                    heroTag: "gallery_btn",
                    backgroundColor: Colors.grey[800],
                    onPressed: pickFromGallery,
                    child: const Icon(Icons.photo_library, color: Colors.white),
                  ),
                  GestureDetector(
                    onTap: takePhoto,
                    child: Container(
                      height: 80,
                      width: 80,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 4),
                        color: Colors.white24,
                      ),
                      child: Center(
                        child: Container(
                          height: 60,
                          width: 60,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 56),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';

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
  File? processedImage;
  final ImagePicker _picker = ImagePicker();

  // আপনার রানিং Localtunnel URL
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

  void updateProgress(double percent, String msg) {
    setState(() {
      processPercentage = percent;
      statusMessage = msg;
    });
  }

  // গ্যালারি থেকে ছবি সিলেক্ট করা
  Future<void> pickFromGallery() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);
    if (image != null) {
      processImageFile(File(image.path));
    }
  }

  // ক্যামেরা দিয়ে ছবি তোলা
  Future<void> takePhoto() async {
    if (controller == null || !controller!.value.isInitialized || isProcessing) return;

    try {
      final image = await controller!.takePicture();
      processImageFile(File(image.path));
    } catch (e) {
      showDialogMsg("Error", "ক্যামেরা থেকে ছবি তুলতে সমস্যা হয়েছে: $e");
    }
  }

  // ছবি সার্ভারে পাঠানো ও প্রসেসিং
  Future<void> processImageFile(File rawImageFile) async {
    setState(() {
      isProcessing = true;
      processedImage = null;
      processPercentage = 0.05;
      statusMessage = "ছবি প্রস্তুত করা হচ্ছে...";
    });

    try {
      updateProgress(0.15, "সার্ভারে কানেক্ট করা হচ্ছে...");
      
      var uri = Uri.parse(apiUrl);
      var request = http.MultipartRequest('POST', uri);
      request.headers['Bypass-Tunnel-Reminder'] = 'true';
      
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

      var streamedResponse = await request.send().timeout(const Duration(seconds: 45));
      
      updateProgress(0.65, "AI পোর্ট্রেট ফিল্টার প্রয়োগ হচ্ছে (৬৫%)...");

      if (streamedResponse.statusCode == 200) {
        updateProgress(0.85, "প্রসেসড ছবি ডাউনলোড হচ্ছে (৮৫%)...");
        
        List<int> bytes = [];
        int totalReceived = 0;
        int? contentLength = streamedResponse.contentLength;

        await for (var chunk in streamedResponse.stream) {
          bytes.addAll(chunk);
          totalReceived += chunk.length;
          if (contentLength != null && contentLength > 0) {
            double downloadProgress = 0.85 + ((totalReceived / contentLength) * 0.10);
            updateProgress(downloadProgress, "ডাউনলোড হচ্ছে ${(downloadProgress * 100).toInt()}%...");
          }
        }

        updateProgress(0.95, "ফোন গ্যালারিতে সেভ করা হচ্ছে...");

        // স্থায়ী ফোল্ডারে ফাইল রাইট
        final dir = await getTemporaryDirectory();
        File tempFile = File('${dir.path}/AI_Enhanced_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await tempFile.writeAsBytes(bytes);

        // Gal প্যাকেজ দিয়ে ফোনের গ্যালারিতে আসল সেভ
        await Gal.putImage(tempFile.path);

        updateProgress(1.0, "সম্পন্ন হয়েছে!");

        setState(() {
          processedImage = tempFile;
          isProcessing = false;
        });

        showDialogMsg("Success", "ছবিটি সফলভাবে AI দিয়ে এনহ্যান্স করা হয়েছে এবং আপনার ফোন গ্যালারিতে সেভ হয়েছে!");
      } else {
        setState(() => isProcessing = false);
        showDialogMsg("Server Failure", "সার্ভার রেসপন্স দেয়নি (Code: ${streamedResponse.statusCode})। Localtunnel রানিং আছে কিনা চেক করুন।");
      }
    } catch (e) {
      setState(() => isProcessing = false);
      showDialogMsg("Connection Error", "সমস্যা: $e\nইন্টারনেট বা সার্ভার সংযোগ পরীক্ষা করুন।");
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
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // প্রসেস হওয়া ছবি থাকলে সেটি ফুলস্ক্রিন প্রিভিউ দেখাবে
          if (processedImage != null)
            Positioned.fill(
              child: Image.file(processedImage!, fit: BoxFit.contain),
            )
          else if (controller != null && controller!.value.isInitialized)
            Positioned.fill(child: CameraPreview(controller!))
          else
            const Center(child: CircularProgressIndicator(color: Colors.white)),

          // % পার্সেন্টেজ লোডিং প্যানেল
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

          // প্রিভিউ থেকে পুনরায় ক্যামেরা মোডে ফেরার বাটন
          if (processedImage != null && !isProcessing)
            Positioned(
              top: 50,
              left: 20,
              child: CircleAvatar(
                backgroundColor: Colors.black54,
                child: IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () {
                    setState(() {
                      processedImage = null;
                    });
                  },
                ),
              ),
            ),

          // বটম কন্ট্রোল বার (ক্যামেরা ও গ্যালারি বাটন)
          if (processedImage == null && !isProcessing)
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // গ্যালারি থেকে ছবি সিলেক্ট করার বাটন
                  FloatingActionButton(
                    heroTag: "gallery_btn",
                    backgroundColor: Colors.grey[800],
                    onPressed: pickFromGallery,
                    child: const Icon(Icons.photo_library, color: Colors.white),
                  ),
                  // ছবি তোলার শাটান বাটন
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
                  const SizedBox(width: 56), // ব্যালেন্সের জন্য স্পেস
                ],
              ),
            ),
        ],
      ),
    );
  }
}

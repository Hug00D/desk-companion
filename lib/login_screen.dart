import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:rive/rive.dart' as rv;
import 'face_detection_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _pwController = TextEditingController();
  bool _isSignUp = false; // 切換註冊/登入
  bool _isLoading = false;

  void _toggleMode() {
    setState(() => _isSignUp = !_isSignUp);
  }

  Future<void> _handleAction() async {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (context) => const FaceDetectionScreen()),
    );
    return;

    final email = _emailController.text.trim();
    final password = _pwController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("請填寫 Email 與密碼")));
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 模擬器連本地後端 IP
      const String baseUrl = "http://10.0.2.2:8080/api/v1";

      final url = _isSignUp
          ? Uri.parse("$baseUrl/users/register")
          : Uri.parse("$baseUrl/auth/login");

      // 根據文件構造 Request Body
      final Map<String, dynamic> requestBody = {
        "email": email,
        "password": password,
      };

      if (_isSignUp) {
        // 註冊時必須多傳 displayName
        requestBody["displayName"] = "New User"; // 之後可以加一個欄位讓使用者填
      }

      final response = await http.post(
        url,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode(requestBody),
      );

      if (!mounted) return;

      final data = jsonDecode(response.body);

      if (response.statusCode == 200 || response.statusCode == 201) {
        // 成功！
        print("Success: ${data['message'] ?? 'Action Successful'}");

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const FaceDetectionScreen()),
        );
      } else {
        // 依照文件處理錯誤格式 (BusinessException / Validation)
        String errorMsg = data['message'] ?? "未知錯誤";
        if (data['errorCode'] == "VALIDATION_ERROR" && data['details'] != null) {
          errorMsg = "驗證失敗: ${data['details']}";
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.redAccent),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("網路連線失敗: $e")),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. 動態背景
          const SizedBox.expand(
            child: rv.RiveAnimation.asset('assets/test.riv', fit: BoxFit.cover),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(color: Colors.black.withOpacity(0.4)),
            ),
          ),

          // 2. 主要 UI
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 35),
              child: Column(
                children: [
                  _buildHeader(),
                  const SizedBox(height: 50),

                  // 輸入框組
                  _buildGlassField(Icons.email_outlined, "Email", _emailController),
                  const SizedBox(height: 15),
                  _buildGlassField(Icons.lock_outline, "Password", _pwController, isObscure: true),

                  // 忘記密碼 (只有登入模式顯示)
                  if (!_isSignUp)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () {}, // 忘記密碼邏輯預留
                        child: Text("Forgot Password?", style: TextStyle(color: Colors.white.withOpacity(0.5))),
                      ),
                    ),

                  const SizedBox(height: 25),

                  // 主按鈕 (登入/註冊)
                  _buildMainButton(),

                  const SizedBox(height: 30),

                  // --- 分隔線 ---
                  Row(
                    children: [
                      Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Text("OR", style: TextStyle(color: Colors.white.withOpacity(0.3))),
                      ),
                      Expanded(child: Divider(color: Colors.white.withOpacity(0.2))),
                    ],
                  ),

                  const SizedBox(height: 30),

                  // Google 登入按鈕
                  _buildGoogleButton(),

                  const SizedBox(height: 40),

                  // 切換模式按鈕
                  GestureDetector(
                    onTap: _toggleMode,
                    child: RichText(
                      text: TextSpan(
                        text: _isSignUp ? "Already have an account? " : "New here? ",
                        style: TextStyle(color: Colors.white.withOpacity(0.6)),
                        children: [
                          TextSpan(
                            text: _isSignUp ? "Sign In" : "Create Account",
                            style: const TextStyle(color: Color(0xFF79D2F5), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- UI 元件拆解 ---

  Widget _buildHeader() {
    return Column(
      children: [
        const Icon(Icons.auto_awesome_motion_rounded, size: 50, color: Color(0xFF79D2F5)),
        const SizedBox(height: 15),
        Text(
          _isSignUp ? "JOIN US" : "WELCOME BACK",
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 5),
        ),
      ],
    );
  }

  Widget _buildGlassField(IconData icon, String hint, TextEditingController controller, {bool isObscure = false}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.15)),
          ),
          child: TextField(
            controller: controller,
            obscureText: isObscure,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              icon: Icon(icon, color: const Color(0xFF79D2F5), size: 20),
              hintText: hint,
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
              border: InputBorder.none,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMainButton() {
    return InkWell(
      onTap: _isLoading ? null : _handleAction,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        width: double.infinity,
        height: 55,
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF57BEEB), Color(0xFF2F7ED8)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(color: const Color(0xFF57BEEB).withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 6))],
        ),
        child: Center(
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
              : Text(_isSignUp ? "REGISTER" : "SIGN IN", style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
        ),
      ),
    );
  }

  Widget _buildGoogleButton() {
    return OutlinedButton(
      onPressed: () {}, // Google 登入邏輯
      style: OutlinedButton.styleFrom(
        fixedSize: const Size(double.infinity, 55),
        side: BorderSide(color: Colors.white.withOpacity(0.2)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        backgroundColor: Colors.white.withOpacity(0.05),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // 這邊暫用 Icon 代替 Google Logo
          const Icon(Icons.g_mobiledata_rounded, color: Colors.white, size: 30),
          const SizedBox(width: 10),
          Text("Continue with Google", style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 15)),
        ],
      ),
    );
  }
}
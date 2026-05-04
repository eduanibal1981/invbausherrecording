import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;

class AIResearchScreen extends StatefulWidget {
  const AIResearchScreen({super.key});

  @override
  State<AIResearchScreen> createState() => _AIResearchScreenState();
}

class _AIResearchScreenState extends State<AIResearchScreen> {
  final _apiKeyController = TextEditingController();
  final _promptController = TextEditingController();
  final List<Map<String, dynamic>> _chatHistory = [];
  
  bool _hasApiKey = false;
  bool _isLoading = false;
  String _loadingMessage = '';
  
  // Data caching
  String? _cachedCsvData;

  @override
  void initState() {
    super.initState();
    _loadApiKey();
  }

  Future<void> _loadApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    final key = prefs.getString('gemini_api_key');
    if (key != null && key.isNotEmpty) {
      setState(() {
        _apiKeyController.text = key;
        _hasApiKey = true;
      });
    }
  }

  Future<void> _saveApiKey() async {
    final key = _apiKeyController.text.trim();
    if (key.isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('gemini_api_key', key);
    
    setState(() {
      _hasApiKey = true;
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('API Key Saved. You can now start researching.')),
    );
  }

  Future<void> _clearApiKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('gemini_api_key');
    setState(() {
      _apiKeyController.clear();
      _hasApiKey = false;
      _chatHistory.clear();
      _cachedCsvData = null;
    });
  }

  Future<String> _fetchAndFormatData() async {
    if (_cachedCsvData != null) return _cachedCsvData!;

    setState(() {
      _loadingMessage = 'Gathering patient data...';
      _isLoading = true;
    });

    try {
      // We use the new RPC to get the latest labs for all active patients
      final response = await Supabase.instance.client.rpc('get_all_latest_labs');
      final labs = List<Map<String, dynamic>>.from(response);

      if (labs.isEmpty) {
        return "No patient data found.";
      }

      // Convert to CSV string
      final headers = labs.first.keys.toList();
      final StringBuffer csvBuffer = StringBuffer();
      
      // Write headers
      csvBuffer.writeln(headers.join(','));
      
      // Write rows
      for (var row in labs) {
        final rowValues = headers.map((h) => row[h]?.toString() ?? '').join(',');
        csvBuffer.writeln(rowValues);
      }

      _cachedCsvData = csvBuffer.toString();
      return _cachedCsvData!;
    } catch (e) {
      throw Exception('Failed to fetch data: $e');
    }
  }

  Future<void> _askAI() async {
    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) return;

    final apiKey = _apiKeyController.text.trim();
    if (apiKey.isEmpty) return;

    setState(() {
      _chatHistory.add({'role': 'user', 'text': prompt});
      _promptController.clear();
      _isLoading = true;
      _loadingMessage = 'Thinking...';
    });

    try {
      // 1. Fetch Data
      final dataCsv = await _fetchAndFormatData();

      // 3. Construct the message
      final fullPrompt = "Data context (CSV):\n$dataCsv\n\nUser Question:\n$prompt";

      GenerateContentResponse? response;
      
      try {
        final model = GenerativeModel(
          model: 'gemini-2.5-flash',
          apiKey: apiKey,
          systemInstruction: Content.system(
            "You are a helpful data analyst AI integrated directly into a nephrology clinic's database system. "
            "You will be provided with the latest patient lab results and their vascular access type (vaccess). "
            "Analyze the data and answer the user's questions clearly and concisely. "
            "Identify patients by their pcid. Never reveal actual patient names, only pcid. "
            "If calculating averages or statistics, show your logic briefly. "
            "IMPORTANT RULE: Never mention that data was provided to you as a CSV or inside a prompt. "
            "Speak naturally as if you are directly querying and reading the clinic's secure database yourself."
          )
        );
        response = await model.generateContent([Content.text(fullPrompt)]);
      } catch (e) {
        // Fallback to gemini-2.5-pro
        try {
          final fallbackModel = GenerativeModel(
            model: 'gemini-2.5-pro',
            apiKey: apiKey,
          );
          final fallbackPrompt = "You are a helpful data analyst AI integrated directly into a nephrology clinic's database system. You will be provided with the latest patient lab results and their vascular access type (vaccess). Analyze the data and answer the user's questions clearly and concisely. Identify patients by their pcid. Never reveal actual patient names, only pcid. If calculating averages or statistics, show your logic briefly. IMPORTANT RULE: Never mention that data was provided to you as a CSV or inside a prompt. Speak naturally as if you are directly querying and reading the clinic's secure database yourself.\n\n$fullPrompt";
          response = await fallbackModel.generateContent([Content.text(fallbackPrompt)]);
        } catch (innerError) {
           throw Exception("Both gemini-1.5-flash and gemini-1.5-pro failed. Error: $e");
        }
      }

      setState(() {
        _chatHistory.add({
          'role': 'model',
          'text': response?.text ?? 'No response generated.'
        });
        _isLoading = false;
      });
    } catch (e) {
      // Try to fetch available models to help the user debug
      String availableModelsStr = "";
      try {
        final url = Uri.parse('https://generativelanguage.googleapis.com/v1beta/models?key=$apiKey');
        final httpResponse = await http.get(url);
        if (httpResponse.statusCode == 200) {
          availableModelsStr = "\n\nAvailable Models for your key: ${httpResponse.body}";
        }
      } catch (_) {}

      setState(() {
        _chatHistory.add({
          'role': 'model',
          'text': 'Error: $e$availableModelsStr\n\nPlease ensure your Google AI Studio API key has access to these models.'
        });
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AI Research Assistant'),
        actions: [
          if (_hasApiKey)
            IconButton(
              icon: const Icon(Icons.key_off),
              tooltip: 'Clear API Key',
              onPressed: _clearApiKey,
            ),
        ],
      ),
      body: !_hasApiKey ? _buildApiKeySetup() : _buildChatInterface(),
    );
  }

  Widget _buildApiKeySetup() {
    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 500),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.auto_awesome, size: 64, color: Colors.teal),
            const SizedBox(height: 24),
            const Text(
              'Welcome to AI Data Research',
              style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'To use this feature for free, please enter a Google Gemini API Key. '
              'You can get one for free at aistudio.google.com/app/apikey.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black54),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _apiKeyController,
              decoration: const InputDecoration(
                labelText: 'Gemini API Key',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.vpn_key),
              ),
              obscureText: true,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saveApiKey,
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: const Text('Save API Key & Start', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatInterface() {
    return Column(
      children: [
        // Information Header
        Container(
          padding: const EdgeInsets.all(12),
          color: Colors.blue.shade50,
          width: double.infinity,
          child: Row(
            children: const [
              Icon(Icons.info_outline, color: Colors.blue),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'The AI has access to the latest lab results (CBC, Bone Profile, Iron) for all active patients. Ask questions like "What is the average HB?" or "List pcids of patients with Calcium > 2.6".',
                  style: TextStyle(fontSize: 13, color: Colors.blue),
                ),
              ),
            ],
          ),
        ),
        
        // Chat History
        Expanded(
          child: _chatHistory.isEmpty
              ? const Center(
                  child: Text(
                    'Ask a question to begin your research!',
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _chatHistory.length,
                  itemBuilder: (context, index) {
                    final message = _chatHistory[index];
                    final isUser = message['role'] == 'user';
                    
                    return Align(
                      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
                      child: Container(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.8,
                        ),
                        margin: const EdgeInsets.only(bottom: 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: isUser ? Colors.teal.shade100 : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(16).copyWith(
                            bottomRight: isUser ? const Radius.circular(0) : const Radius.circular(16),
                            bottomLeft: !isUser ? const Radius.circular(0) : const Radius.circular(16),
                          ),
                        ),
                        child: SelectableText(
                          message['text'] ?? '',
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                    );
                  },
                ),
        ),

        // Loading Indicator
        if (_isLoading)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 8),
                Text(_loadingMessage, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          ),

        // Input Field
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _promptController,
                  decoration: const InputDecoration(
                    hintText: 'Type your research question...',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(24)),
                    ),
                    contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  onSubmitted: (_) => _askAI(),
                  enabled: !_isLoading,
                ),
              ),
              const SizedBox(width: 8),
              FloatingActionButton(
                onPressed: _isLoading ? null : _askAI,
                backgroundColor: _isLoading ? Colors.grey : Colors.teal,
                elevation: 0,
                child: const Icon(Icons.send),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

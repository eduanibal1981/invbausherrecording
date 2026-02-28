import re

file_path = r'c:\Projects\invbausherrecording\lib\services\cloudinary_service.dart'
try:
    with open(file_path, 'r', encoding='utf-8') as f:
        text = f.read()
except FileNotFoundError:
    print("File not found")
    exit(1)

# 1. doppplerslinks check (around line 117-130)
check_dopp_pattern = re.compile(r"final checkUrl = Uri.parse\(.*?'\$\{CloudinaryConfig\.supabaseUrl\}/rest/v1/doppplerslinks\?pcid=eq\.\$pcid&thumbnail_url=eq\.\$\{Uri\.encodeComponent\(thumbnailUrl\)\}'.*?\);.+?final checkResponse = await http\.get\(.+?headers: \{.*?'apikey': CloudinaryConfig\.supabaseKey,.*?'Authorization': 'Bearer \$\{CloudinaryConfig\.supabaseKey\}',.*?\},.+?\);.+?final existing = json\.decode\(checkResponse\.body\);", re.DOTALL)

check_dopp_repl = r'''final existing = await Supabase.instance.client
          .from('doppplerslinks')
          .select()
          .eq('pcid', pcid)
          .eq('thumbnail_url', thumbnailUrl);'''
text = check_dopp_pattern.sub(check_dopp_repl, text)
text = text.replace('''      if (existing.length > 0) {''', '''      if ((existing as List).isNotEmpty) {''')

# 2. doppplerslinks insert
insert_dopp_pattern = re.compile(r"final supabasePostUrl = Uri.parse\(.*?'\$\{CloudinaryConfig\.supabaseUrl\}/rest/v1/doppplerslinks',.*?\);.+?final supabaseResponse = await http\.post\(.+?headers: \{.+?\},.+?body: json\.encode\(\{.+?'pcid': pcid,.+?'piclink': mediumUrl,.*?// Keep for backward compatibility.+?'thumbnail_url': thumbnailUrl,.+?'medium_url': mediumUrl,.+?'large_url': largeUrl,.+?'full_url': fullUrl,.+?\}\),.+?\);.+?// Step 8: Handle Supabase response.+?if \(supabaseResponse\.statusCode == 201 \|\|.+?supabaseResponse\.statusCode == 200\) \{", re.DOTALL)

insert_dopp_repl = r'''try {
        await Supabase.instance.client.from('doppplerslinks').insert({
          'pcid': pcid,
          'piclink': mediumUrl,
          'thumbnail_url': thumbnailUrl,
          'medium_url': mediumUrl,
          'large_url': largeUrl,
          'full_url': fullUrl,
        });
        
        if (true) {'''
text = insert_dopp_pattern.sub(insert_dopp_repl, text)

# Delete doppler image
del_dopp_pattern = re.compile(r"final url = Uri.parse\(.*?'\$\{CloudinaryConfig\.supabaseUrl\}/rest/v1/doppplerslinks\?id=eq\.\$id',.*?\);.+?final response = await http\.delete\(.+?url,.+?headers: \{.+?\},.+?\);.+?if \(response\.statusCode == 200 \|\| response\.statusCode == 204\) \{.+?return CloudinaryDeleteResult\(success: true\);.+?\}.+?final errorBody = _tryDecodeErrorMessage\(response\.body\) \?\? response\.body;.+?return CloudinaryDeleteResult\(.+?success: false,.+?message: '\$\{response\.statusCode\} - \$errorBody',.+?\);", re.DOTALL)

del_dopp_repl = r'''try {
        await Supabase.instance.client
            .from('doppplerslinks')
            .delete()
            .eq('id', id);
        return CloudinaryDeleteResult(success: true);
    } catch (dbError) {
        return CloudinaryDeleteResult(
          success: false,
          message: dbError.toString(),
        );
    }'''
text = del_dopp_pattern.sub(del_dopp_repl, text)

# Fetch doppler images
fetch_dopp_pattern = re.compile(r"final url = Uri\.parse\(.*?'\$\{CloudinaryConfig\.supabaseUrl\}/rest/v1/doppplerslinks\?pcid=eq\.\$pcid&order=created_at\.desc',.*?\);.+?final response = await http\.get\(.+?headers: \{.+?\},.+?\);.+?if \(response\.statusCode == 200\) \{.+?return List<Map<String, dynamic>>\.from\(json\.decode\(response\.body\)\);.+?\}", re.DOTALL)
fetch_dopp_repl = r'''final response = await Supabase.instance.client
            .from('doppplerslinks')
            .select()
            .eq('pcid', pcid)
            .order('created_at', ascending: false);

      if (response != null) {
        return List<Map<String, dynamic>>.from(response);
      }'''
text = fetch_dopp_pattern.sub(fetch_dopp_repl, text)

# --- ECG Check ---
check_ecg_pattern = re.compile(r"final checkUrl = Uri.parse\(.*?'\$\{CloudinaryConfig\.supabaseUrl\}/rest/v1/ecg_links\?pcid=eq\.\$pcid&thumbnail_url=eq\.\$\{Uri\.encodeComponent\(thumbnailUrl\)\}'.*?\);.+?final checkResponse = await http\.get\(.+?headers: \{.*?'apikey': CloudinaryConfig\.supabaseKey,.*?'Authorization': 'Bearer \$\{CloudinaryConfig\.supabaseKey\}',.*?\},.+?\);.+?final existing = json\.decode\(checkResponse\.body\);", re.DOTALL)
check_ecg_repl = r'''final existing = await Supabase.instance.client
          .from('ecg_links')
          .select()
          .eq('pcid', pcid)
          .eq('thumbnail_url', thumbnailUrl);'''
text = check_ecg_pattern.sub(check_ecg_repl, text)
text = text.replace('''if (existing is List && existing.isNotEmpty) {''', '''if ((existing as List).isNotEmpty) {''')

# --- ECG Insert ---
insert_ecg_pattern = re.compile(r"final supabasePostUrl = Uri.parse\(.*?'\$\{CloudinaryConfig\.supabaseUrl\}/rest/v1/ecg_links',.*?\);.+?final supabaseResponse = await http\.post\(.+?headers: \{.+?\},.+?body: json\.encode\(\{.+?'pcid': pcid,.+?'piclink': mediumUrl,.+?'thumbnail_url': thumbnailUrl,.+?'medium_url': mediumUrl,.+?'large_url': largeUrl,.+?'full_url': fullUrl,.+?\}\),.+?\);.+?if \(supabaseResponse\.statusCode == 201 \|\|.+?supabaseResponse\.statusCode == 200\) \{", re.DOTALL)

insert_ecg_repl = r'''try {
        await Supabase.instance.client.from('ecg_links').insert({
          'pcid': pcid,
          'piclink': mediumUrl,
          'thumbnail_url': thumbnailUrl,
          'medium_url': mediumUrl,
          'large_url': largeUrl,
          'full_url': fullUrl,
        });
        
        if (true) {'''
text = insert_ecg_pattern.sub(insert_ecg_repl, text)

# --- Delete ECG ---
del_ecg_pattern = re.compile(r"final url = Uri\.parse\(.*?'\$\{CloudinaryConfig\.supabaseUrl\}/rest/v1/ecg_links\?id=eq\.\$id',.*?\);.+?final response = await http\.delete\(.+?url,.+?headers: \{.+?\},.+?\);.+?if \(response\.statusCode == 200 \|\| response\.statusCode == 204\) \{.+?return CloudinaryDeleteResult\(.+?success: true,.+?message: 'Image deleted from Cloudinary and Supabase',.+?\);.+?\}.+?final errorBody = _tryDecodeErrorMessage\(response\.body\) \?\? response\.body;.+?return CloudinaryDeleteResult\(.+?success: false,.+?message:.+?'Deleted from Cloudinary but failed to remove from Supabase: \$\{response\.statusCode\} - \$errorBody',.+?\);", re.DOTALL)

del_ecg_repl = r'''try {
        await Supabase.instance.client
            .from('ecg_links')
            .delete()
            .eq('id', id);
        
        return CloudinaryDeleteResult(
          success: true,
          message: 'Image deleted from Cloudinary and Supabase',
        );
      } catch (dbError) {
        return CloudinaryDeleteResult(
          success: false,
          message:
              'Deleted from Cloudinary but failed to remove from Supabase: ${dbError.toString()}',
        );
      }'''
text = del_ecg_pattern.sub(del_ecg_repl, text)

# --- Fetch ECG ---
fetch_ecg_pattern = re.compile(r"final url = Uri\.parse\(.*?'\$\{CloudinaryConfig\.supabaseUrl\}/rest/v1/ecg_links\?pcid=eq\.\$pcid&order=created_at\.desc',.*?\);.+?final response = await http\.get\(.+?headers: \{.+?\},.+?\);.+?if \(response\.statusCode == 200\) \{.+?return List<Map<String, dynamic>>\.from\(json\.decode\(response\.body\)\);.+?\}", re.DOTALL)
fetch_ecg_repl = r'''final response = await Supabase.instance.client
            .from('ecg_links')
            .select()
            .eq('pcid', pcid)
            .order('created_at', ascending: false);

      if (response != null) {
        return List<Map<String, dynamic>>.from(response);
      }'''
text = fetch_ecg_pattern.sub(fetch_ecg_repl, text)

# --- Update ECG Note ---
patch_ecg_pattern = re.compile(r"final url = Uri\.parse\(.*?'\$\{CloudinaryConfig\.supabaseUrl\}/rest/v1/ecg_links\?id=eq\.\$id',.*?\);.+?final response = await http\.patch\(.+?headers: \{.+?\},.+?body: json\.encode\(\{'clinicalnote': note\}\),.+?\);.+?return response\.statusCode >= 200 && response\.statusCode < 300;", re.DOTALL)
patch_ecg_repl = r'''await Supabase.instance.client
          .from('ecg_links')
          .update({'clinicalnote': note})
          .eq('id', id);
      return true;'''
text = patch_ecg_pattern.sub(patch_ecg_repl, text)

# --- Doppler Video Insert ---
insert_dopp_vid_pattern = re.compile(r"final supabasePostUrl = Uri.parse\(.*?'\$\{CloudinaryConfig\.supabaseUrl\}/rest/v1/doppplerslinks',.*?\);.+?final supabaseResponse = await http\.post\(.+?headers: \{.+?\},.+?body: json\.encode\(\{.+?'pcid': pcid,.+?'piclink': fullUrl,.+?'thumbnail_url': thumbnailUrl,.+?'medium_url': thumbnailUrl,.+?// Use thumbnail for medium too.+?'large_url': fullUrl,.+?'full_url': fullUrl,.+?\}\),.+?\);.+?if \(supabaseResponse\.statusCode == 201 \|\|.+?supabaseResponse\.statusCode == 200\) \{", re.DOTALL)

insert_dopp_vid_repl = r'''try {
        await Supabase.instance.client.from('doppplerslinks').insert({
          'pcid': pcid,
          'piclink': fullUrl,
          'thumbnail_url': thumbnailUrl,
          'medium_url': thumbnailUrl,
          'large_url': fullUrl,
          'full_url': fullUrl,
        });

        if (true) {'''
text = insert_dopp_vid_pattern.sub(insert_dopp_vid_repl, text)

target_err_block = """} else {
        final errorBody =
            _tryDecodeErrorMessage(supabaseResponse.body) ??
            supabaseResponse.body;
        return CloudinaryUploadResult(
          success: false,
          message:
              'Uploaded to Cloudinary but failed to save to Supabase: ${supabaseResponse.statusCode} - $errorBody',"""

replace_err_block = """} else {
          // Unreachable
      }
    } catch (dbError) {
        return CloudinaryUploadResult(
          success: false,
          message:
              'Uploaded to Cloudinary but failed to save to Supabase: ${dbError.toString()}',"""

text = text.replace(target_err_block, replace_err_block)

text = text.replace('import \'package:http/http.dart\' as http;', '// import \'package:http/http.dart\' as http;')

with open(file_path, 'w', encoding='utf-8') as f:
    f.write(text)

print("Replacement complete.")

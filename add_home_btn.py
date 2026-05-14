import os
import glob
import re

home_button = '''
          IconButton(
            icon: const Icon(Icons.home),
            tooltip: 'Return to Home',
            onPressed: () {
              Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),'''

files = glob.glob('c:/Projects/invbausherrecording/lib/**/*.dart', recursive=True)
exclude = ['patient_list_screen.dart', 'main.dart', 'filter_screen.dart']

for file in files:
    if any(e in file for e in exclude): continue
    
    with open(file, 'r', encoding='utf-8') as f:
        content = f.read()
        
    if 'appBar: AppBar(' in content and 'Return to Home' not in content:
        idx = content.find('appBar: AppBar(')
        if idx != -1:
            title_idx = content.find('title:', idx)
            if title_idx != -1:
                end_title_idx = content.find(',', title_idx)
                if end_title_idx != -1:
                    new_content = content[:end_title_idx+1] + '\n        actions: [' + home_button + '\n        ],' + content[end_title_idx+1:]
                    with open(file, 'w', encoding='utf-8') as f:
                        f.write(new_content)
                    print(f'Updated {file}')

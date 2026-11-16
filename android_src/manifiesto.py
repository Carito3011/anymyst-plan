# Ajusta el AndroidManifest generado por flutter create.
import sys
p = sys.argv[1]
s = open(p).read()
# Recibir guiones desde Anymyst Script
i = s.index('</intent-filter>') + len('</intent-filter>')
s = s[:i] + """
            <intent-filter>
                <action android:name="android.intent.action.SEND"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <data android:mimeType="application/x-anymyst-script"/>
            </intent-filter>""" + s[i:]
open(p, 'w').write(s)

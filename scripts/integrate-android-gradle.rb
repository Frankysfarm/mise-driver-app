path = ARGV.fetch(0)
content = File.read(path)
dependencies = [
  'implementation "com.google.android.gms:play-services-location:21.3.0"',
  'implementation "androidx.security:security-crypto:1.1.0-alpha06"',
]

dependencies.each do |dependency|
  content = content.gsub(/^[ \t]*#{Regexp.escape(dependency)}[ \t]*\n?/, "")
end

marker = /^dependencies \{\s*$/
abort("Gradle dependencies block not found") unless content.match?(marker)
content = content.sub(/^dependencies \{\n(?:[ \t]*\n)*/, "dependencies {\n")
insertion = dependencies.map { |dependency| "    #{dependency}" }.join("\n")
content = content.sub(marker) { |line| "#{line}\n#{insertion}" }
File.write(path, content)

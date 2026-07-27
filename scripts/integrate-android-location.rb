require "rexml/document"

path = ARGV.fetch(0)
doc = REXML::Document.new(File.read(path))
manifest = doc.root
android = "http://schemas.android.com/apk/res/android"
permissions = %w[
  ACCESS_FINE_LOCATION ACCESS_COARSE_LOCATION ACCESS_BACKGROUND_LOCATION
  FOREGROUND_SERVICE FOREGROUND_SERVICE_LOCATION
]
permissions.each do |permission|
  name = "android.permission.#{permission}"
  next if manifest.elements.to_a("uses-permission").any? { |node| node.attributes["android:name"] == name }
  node = manifest.add_element("uses-permission")
  node.add_attribute("android:name", name)
end
application = manifest.elements["application"] or abort("AndroidManifest has no application")
unless application.elements.to_a("service").any? { |node| node.attributes["android:name"] == ".location.MiseLocationService" }
  service = application.add_element("service")
  service.add_attribute("android:name", ".location.MiseLocationService")
  service.add_attribute("android:exported", "false")
  service.add_attribute("android:foregroundServiceType", "location")
  service.add_attribute("android:stopWithTask", "false")
end
formatter = REXML::Formatters::Pretty.new(2)
formatter.compact = true
File.open(path, "w") { |file| formatter.write(doc, file); file.write("\n") }

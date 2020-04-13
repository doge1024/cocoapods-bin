gem uninstall cocoapods-bin
gem uninstall cocoapods-bin-framework
echo "\ngem build cocoapods-bin\n"
gem build cocoapods-bin.gemspec
OUTPUT="$(find . -name *gem)"
echo "\ngem install cocoapods-bin\n"
gem install --local ${OUTPUT}
rm ${OUTPUT}
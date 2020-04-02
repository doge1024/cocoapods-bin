gem uninstall cocoapods-bin
echo "\ngem build cocoapods-bin\n"
gem build cocoapods-bin.gemspec
OUTPUT="$(find . -name *gem)"
echo "\ngem install cocoapods-bin\n"
gem install --local ${OUTPUT}
rm ${OUTPUT}
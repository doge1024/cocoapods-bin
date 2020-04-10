# frozen_string_literal: true

# copy from https://github.com/CocoaPods/cocoapods-packager

require 'cocoapods-bin/helpers/framework.rb'
require 'English'

module CBin
  class Framework
    class Builder
      include Pod

      def initialize(spec, file_accessor, platform, source_dir, use_framework=true)
        @spec = spec
        @source_dir = source_dir
        @file_accessor = file_accessor
        @platform = platform
        @vendored_libraries = (file_accessor.vendored_static_frameworks + file_accessor.vendored_static_libraries).map(&:to_s)
        @use_framework = use_framework
      end

      def build
        UI.section("Building dynmic framework #{@spec}") do
          defines = compile

          build_sim_dynmic_framework(defines)

          output = framework.fwk_path + Pathname.new(@spec.name)
          build_dynmic_framework_for_ios(output)

          merge_swift_header
          copy_resources
          copy_license
          cp_to_source_dir
        end
      end

      private

      def cp_to_source_dir
        target_dir = "#{@source_dir}/#{framework_name}"
        FileUtils.rm_rf(target_dir) if File.exist?(target_dir)

        `cp -fa #{@platform}/#{framework_name} #{@source_dir}`
      end

      def build_sim_dynmic_framework(defines)
        UI.message 'Building simulator libraries'
        xcodebuild(defines, '-sdk iphonesimulator', 'build-simulator')
      end

      def merge_swift_header
        # <project>-Swift.h 需要区分模拟器和真机
        sim_swift_header = Pathname.new("./build-simulator/#{framework_name}/Headers/#{target_name}-Swift.h")
        iphone_swift_header = Pathname.new("./build/#{framework_name}/Headers/#{target_name}-Swift.h")
        if sim_swift_header.exist? && iphone_swift_header.exist?

          # 拼接文件
          sim_readlines = File.readlines(sim_swift_header)
          sim_readlines.insert(0, *["// 开始模拟器", "#if TARGET_IPHONE_SIMULATOR"])
          sim_readlines << "// 结束模拟器"
          sim_readlines << "#else"
          sim_readlines << "// 开始真机"
          sim_readlines << File.readlines(iphone_swift_header)
          sim_readlines << "// 结束真机"
          sim_readlines << "#endif"

          # 清空源文件
          File.open(iphone_swift_header, "w+") do |aFile|
            # 写入
            for line in sim_readlines do
              aFile.puts line
            end
          end

          `cp -fa #{iphone_swift_header} #{framework.headers_path}`
        end
      end
       
      def copy_license
        UI.message 'Copying license'
        license_file = @spec.license[:file] || 'LICENSE'
        `cp "#{license_file}" .` if Pathname(license_file).exist?
      end

      def copy_resources
        bundles = Dir.glob('./build/*.bundle')
        if bundles.count > 0
          UI.message "Copying bundle files #{bundles}"
          for bundle in bundles do
            `cp -fa #{bundle} #{framework.fwk_path}`
          end
        end
      end

      def use_framework
        return @use_framework
      end

      def framework_name
        return "#{Pathname.new(@spec.name)}.framework"
      end

      def dynmic_libs_in_sandbox(build_dir = 'build')
        Dir.glob("#{build_dir}/#{framework_name}/#{Pathname.new(@spec.name)}")
      end

      def build_dynmic_framework_for_ios(output)
        UI.message "Building ios libraries with archs #{ios_architectures}"
        static_libs = dynmic_libs_in_sandbox('build') + dynmic_libs_in_sandbox('build-simulator') + @vendored_libraries

        # 暂时不过滤 arch, 操作的是framework里面的mach-o文件
        libs = static_libs

        `rm -rf #{framework.fwk_path}/*`
        # 输出之前，先拷贝framework
        # 模拟器 -> 新建framework
        `cp -fRap build-simulator/#{framework_name}/* #{framework.fwk_path}/`
        # 真机 -> 新建framework
        `cp -fRap build/#{framework_name}/* #{framework.fwk_path}/`
        
        # 多拷贝了资源和签名
        `rm -rf #{framework.fwk_path}/_CodeSignature`

        `lipo -create -output #{output} #{libs.join(' ')}`
      end

      def ios_build_options
        "ARCHS=\'#{ios_architectures.join(' ')}\' OTHER_CFLAGS=\'-fembed-bitcode -Qunused-arguments\'"
      end

      def ios_architectures
        archs = %w[x86_64 arm64 armv7 armv7s i386]
        # 默认支持全平台
        # @vendored_libraries.each do |library|
        #   archs = `lipo -info #{library}`.split & archs
        # end
        archs
      end

      def compile
        defines = "GCC_PREPROCESSOR_DEFINITIONS='$(inherited)'"
        defines += ' '
        defines += @spec.consumer(@platform).compiler_flags.join(' ')

        options = ios_build_options
        xcodebuild(defines, options)

        defines
      end

      def target_name
        if @spec.available_platforms.count > 1
          "#{@spec.name}-#{Platform.string_name(@spec.consumer(@platform).platform_name)}"
        else
          @spec.name
        end
      end

      def xcodebuild(defines = '', args = '', build_dir = 'build')
        command = "xcodebuild #{defines} #{args} CONFIGURATION_BUILD_DIR=#{build_dir} clean build -configuration Release -target #{target_name} -project ./Pods.xcodeproj 2>&1"
        output = `#{command}`.lines.to_a

        if $CHILD_STATUS.exitstatus != 0
          raise <<~EOF
            Build command failed: #{command}
            Output:
            #{output.map { |line| "    #{line}" }.join}
          EOF

          Process.exit
        end
      end

      def expand_paths(path_specs)
        path_specs.map do |path_spec|
          Dir.glob(File.join(@source_dir, path_spec))
        end
      end

      def framework
        @framework ||= begin
          framework = Framework.new(@spec.name, @platform.name.to_s)
          framework.make
          framework
        end
      end
    end
  end
end

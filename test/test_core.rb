require_relative "test"

class CoreTest < Test

  def clean
    FileUtils.rm_rf("TestProj")
  end

  def setup
    clean()
    
    contexts = ["context1", "context2"]
    ios_languages = ["en", "ja", "ko", "nl", "zh", "zh-Hans", "zh-Hant"]
    android_languages = ["en", "ja", "ko", "nl", "zh", "zh-rCN", "zh-rTW"]
    base_language = "en"

    # iOS
    for language in ios_languages
      FileUtils.mkdir_p("TestProj/#{language}.lproj")
      File.write("TestProj/#{language}.lproj/Localizable.strings", "")
      for context in contexts
        FileUtils.mkdir_p("TestProj/#{context}/#{language}.lproj")
        File.write("TestProj/#{context}/#{language}.lproj/Localizable.strings", "")
      end
    end
    
    # Android
    for language in android_languages
        if language == base_language
          FileUtils.mkdir_p("TestProj/values")
          File.write("TestProj/values/strings.xml", "")
        else
          FileUtils.mkdir_p("TestProj/values-#{language}")
          File.write("TestProj/values-#{language}/strings.xml", "")
        end
      for context in contexts
        if language == base_language
          FileUtils.mkdir_p("TestProj/#{context}/values")
          File.write("TestProj/#{context}/values/strings.xml", "")
        else
          FileUtils.mkdir_p("TestProj/#{context}/values-#{language}")
          File.write("TestProj/#{context}/values-#{language}/strings.xml", "")
        end
      end
    end

    stub_api_export "en", %{[
      {"term": "greeting", "definition": "Hi, %s!", "context": ""},
      {"term": "welcome", "definition": "Welcome!", "context": ""},
      {"term": "welcome", "definition": "Welcome to App 1!", "context": "context1"},
      {"term": "welcome", "definition": "Welcome to App 2!", "context": "context2"},
      {"term": "thank_you", "definition": "Thank you for downloading $app_name.", "context": ""},
      {"term": "app_name", "definition": "App 1 in EN", "context": "context1"},
      {"term": "app_name", "definition": "App 2 in EN", "context": "context2"}
    ]}
    stub_api_export "nl", %{[
      {"term": "welcome", "definition": "Welkom!", "context": ""},
      {"term": "welcome", "definition": "Welkom bij App 1!", "context": "context1"},
      {"term": "welcome", "definition": "Welkom bij App 2!", "context": "context2"},
      {"term": "thank_you", "definition": "Bedankt voor het downloaden van $app_name.", "context": ""},
      {"term": "app_name", "definition": "App 1 in NL", "context": "context1"},
      {"term": "app_name", "definition": "App 2 in NL", "context": "context2"}
    ]}
    stub_api_export "ko", %{[{"term": "greeting", "definition": "%s님 안녕하세요!", "context": ""}]}
    stub_api_export "zh-CN", %{[{"term": "greeting", "definition": "Simplified 你好, %s!", "context": ""}]}
    stub_api_export "zh-TW", %{[{"term": "greeting", "definition": "Traditional 你好, %s!", "context": ""}]}
  end

  def teardown
    WebMock.reset!
    clean()
  end

  def get_client(type:, languages:, language_alias:nil,
                 path:, path_replace:nil,
                 context_path:nil, context_path_replace:nil)
    configuration = POEditor::Configuration.new(
      :api_key => "TEST",
      :project_id => 12345,
      :type => type,
      :tags => nil,
      :filters => nil,
      :languages => languages,
      :language_alias => language_alias,
      :path => path,
      :path_replace => path_replace,
      :context_path => context_path,
      :context_path_replace => context_path_replace
    )
    POEditor::Core.new(configuration)
  end

  def test_pull_failure
    stub_api_export_failure()
    client = get_client(
      :type => "apple_strings",
      :languages => ["en", "ko"],
      :path => "",
    )
    assert_raises POEditor::Exception do client.pull() end
  end

  def test_pull
    client = get_client(
      :type => "apple_strings",
      :languages => ["en", "ko", "zh-Hans", "zh-Hant"],
      :path => "TestProj/{LANGUAGE}.lproj/Localizable.strings"
    )
    client.pull()

    assert_match "Hi, %@!",
      File.read("TestProj/en.lproj/Localizable.strings")

    assert_match "%@님 안녕하세요!",
      File.read("TestProj/ko.lproj/Localizable.strings")

    assert_match "Simplified 你好, %@!",
      File.read("TestProj/zh-Hans.lproj/Localizable.strings")

    assert_match "Traditional 你好, %@!",
      File.read("TestProj/zh-Hant.lproj/Localizable.strings")

    assert File.read("TestProj/ja.lproj/Localizable.strings").length == 0
    assert File.read("TestProj/zh.lproj/Localizable.strings").length == 0
  end

  def test_pull_language_alias
    client = get_client(
      :type => "apple_strings",
      :languages => ["en", "ko", "zh-Hans", "zh-Hant"],
      :language_alias => {"zh" => "zh-Hans"},
      :path => "TestProj/{LANGUAGE}.lproj/Localizable.strings",
    )
    client.pull()

    assert_match "Simplified 你好, %@!",
      File.read("TestProj/zh-Hans.lproj/Localizable.strings")

    assert_match "Simplified 你好, %@!",
      File.read("TestProj/zh.lproj/Localizable.strings")
  end

  def test_pull_path_replace
    client = get_client(
      :type => "android_strings",
      :languages => ["en", "ko", "zh-rCN", "zh-rTW"],
      :path => "TestProj/values-{LANGUAGE}/strings.xml",
      :path_replace => {"en" => "TestProj/values/strings.xml"},
    )
    client.pull()

    refute File.exist?("TestProj/values-en/strings.xml")
    assert_match "Hi, %s!",
      File.read("TestProj/values/strings.xml")
  end

  def test_context
    client = get_client(
      :type => "android_strings",
      :languages => ["en", "nl"],
      :path => "TestProj/values-{LANGUAGE}/strings.xml",
      :path_replace => {"en" => "TestProj/values/strings.xml"},
      :context_path => "TestProj/{CONTEXT}/values-{LANGUAGE}/strings.xml",
      :context_path_replace => {"en" => "TestProj/{CONTEXT}/values/strings.xml"}
    )
    client.pull()

    assert_match /Welcome!/, File.read("TestProj/values/strings.xml")
    assert_match /Welcome to App 1!/, File.read("TestProj/context1/values/strings.xml")
    assert_match /Welcome to App 2!/, File.read("TestProj/context2/values/strings.xml")

    assert_match /Welkom!/, File.read("TestProj/values-nl/strings.xml")
    assert_match /Welkom bij App 1!/, File.read("TestProj/context1/values-nl/strings.xml")
    assert_match /Welkom bij App 2!/, File.read("TestProj/context2/values-nl/strings.xml")

    assert(!/Welcome!/.match(File.read("TestProj/values-nl/strings.xml")))
    assert(!/Welcome!/.match(File.read("TestProj/context1/values/strings.xml")))
    assert(!/Welcome!/.match(File.read("TestProj/context1/values-nl/strings.xml")))

    assert(!/Welkom!/.match(File.read("TestProj/values/strings.xml")))
    assert(!/Welkom!/.match(File.read("TestProj/context1/values/strings.xml")))
    assert(!/Welkom!/.match(File.read("TestProj/context1/values-nl/strings.xml")))
  end

  def test_placeholders
    client = get_client(
      :type => "android_strings",
      :languages => ["en", "nl"],
      :path => "TestProj/values-{LANGUAGE}/strings.xml",
      :path_replace => {"en" => "TestProj/values/strings.xml"},
      :context_path => "TestProj/{CONTEXT}/values-{LANGUAGE}/strings.xml",
      :context_path_replace => {"en" => "TestProj/{CONTEXT}/values/strings.xml"}
    )
    client.pull()

    assert_match /Thank you for downloading App 1 in EN./, File.read("TestProj/context1/values/strings.xml")
    assert_match /Thank you for downloading App 2 in EN./, File.read("TestProj/context2/values/strings.xml")
    assert_match /Bedankt voor het downloaden van App 1 in NL./, File.read("TestProj/context1/values-nl/strings.xml")
    assert_match /Bedankt voor het downloaden van App 2 in NL./, File.read("TestProj/context2/values-nl/strings.xml")
  end

end

require "json"
require "net/http"

module POEditor
  class Core
    # @return [POEditor::Configuration] The configuration for export
    attr_accessor :configuration

    # @param configuration [POEditor::Configuration]
    def initialize(configuration)
      unless configuration.is_a? Configuration
        raise POEditor::Exception.new \
          "`configuration` should be an `Configuration`"
      end
      @configuration = configuration
    end

    # Request POEditor API
    #
    # @param action [String]
    # @param api_token [String]
    # @param options [Hash{Sting => Object}]
    #
    # @return [Net::HTTPResponse] The response object of API request
    #
    # @see https://poeditor.com/api_reference/ POEditor API Reference
    def api(action, api_token, options={})
      uri = URI("https://api.poeditor.com/v2/#{action}")
      options["api_token"] = api_token
      return Net::HTTP.post_form(uri, options)
    end

    # Pull translations
    def pull()
      UI.puts "\nExport translations"
      for language in @configuration.languages
        UI.puts "  - Exporting '#{language}'"
        content = self.export(:api_key => @configuration.api_key,
                              :project_id => @configuration.project_id,
                              :language => language,
                              :type => @configuration.type,
                              :tags => @configuration.tags,
                              :filters => @configuration.filters)
      end
    end

    # Export translation for specific language
    #
    # @param api_key [String]
    # @param project_jd [String]
    # @param language [String]
    # @param type [String]
    # @param tags [Array<String>]
    # @param filters [Array<String>]
    #
    # @return Downloaded translation content
    def export(api_key:, project_id:, language:, type:, tags:nil, filters:nil)
      options = {
        "id" => project_id,
        "language" => convert_to_poeditor_language(language),
        "type" => "json",
        "tags" => (tags || []).join(","),
        "filters" => (filters || []).join(","),
      }
      response = self.api("projects/export", api_key, options)
      data = JSON(response.body)
      unless data["response"]["status"] == "success"
        code = data["response"]["code"]
        message = data["response"]["message"]
        raise POEditor::Exception.new "#{message} (#{code})"
      end

      download_uri = URI(data["result"]["url"])
      content = Net::HTTP.get(download_uri)

      case type
      when "apple_strings"
        content.gsub!(/(%(\d+\$)?)s/, '\1@')  # %s -> %@
      when "android_strings"
        content.gsub!(/(%(\d+\$)?)@/, '\1s')  # %@ -> %s
      end

      json = JSON.parse content
      groups = json.group_by { |json| json['context'] }
      groups.each do |context, json|
        if context != nil && context != "" && @configuration.context_path == nil
          next # if context path is not defined, skip saving context strings
        end

        case type
        when "apple_strings"
          content = appleStrings(json)
        when "android_strings"
          content = androidStrings(json)
        end

        write(context, language, content)

        for alias_to, alias_from in @configuration.language_alias
          if language == alias_from
            write(context, alias_to, content)
          end
        end
      end
    end

    def appleStrings(json)
      content = ""
      json.each { |item|
        definition = item["definition"]
        content << "\"#{item["term"]}\" = \"#{definition}\";\n"
      }
      return content
    end

    def androidStrings(json)
      content = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources>\n"
      json.each { |item|
        definition = item["definition"]
        content << "  <string name=\"#{item["term"]}\">\"#{definition}\"</string>\n"
      }
      content << "</resources>\n"
      return content
    end

    def convert_to_poeditor_language(language)
      if language.downcase.match(/zh.+(hans|cn)/)
        'zh-CN'
      elsif language.downcase.match(/zh.+(hant|tw)/)
        'zh-TW'
      else
        language
      end
    end

    # Write translation file
    def write(context, language, content)
      path = path_for_context_language(context, language)

      unless path != nil
        raise POEditor::Exception.new "Undefined context path"
      end

      unless File.exist?(path)
        raise POEditor::Exception.new "#{path} doesn't exist"
      end
      File.write(path, content)
      UI.puts "      #{"\xe2\x9c\x93".green} Saved at '#{path}'"
    end

    def path_for_context_language(context, language)
      if context == nil || context == ""
        if @configuration.path_replace[language]
          path = @configuration.path_replace[language]
        else
          path = @configuration.path.gsub("{LANGUAGE}", language)
        end
      else
        if @configuration.context_path_replace[language]
          path = @configuration.context_path_replace[language].gsub("{CONTEXT}", context)
        elsif @configuration.context_path
          path = @configuration.context_path.gsub("{LANGUAGE}", language).gsub("{CONTEXT}", context)
        else
          return nil
        end
      end
    end
  end
end

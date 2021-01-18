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
                              :filters => @configuration.filters,
                              :header => @configuration.header)
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
    # @param header [String]
    #
    # @return Downloaded translation content
    def export(api_key:, project_id:, language:, type:, tags:nil, filters:nil, header:nil)
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
      when "android_strings", "kotlin_strings"
        content.gsub!(/(%(\d+\$)?)@/, '\1s')  # %@ -> %s
      end

      json = JSON.parse content
      groups = json.group_by { |json| json['context'] }
      placeholderItems = []
      groups.each do |context, json|
        if context == "" 
          json.each { |item|
            definition = item["definition"]
            if definition =~ /\$([a-z_]{3,})/
              placeholderItems << item
            end
          }
        end
      end
      groups.each do |context, json|
        if context != "" 
          if @configuration.context_path == nil
            next # if context path is not defined, skip saving context strings
          end
          copyPlaceholderItems(placeholderItems, context, json)
        end

        case type
        when "apple_strings"
          singularContent = singularAppleStrings(json)
          write(context, language, singularContent, :singular)

          if @configuration.path_plural != {}
            pluralContent = pluralAppleStrings(json)
            write(context, language, pluralContent, :plural)
          end
        when "android_strings"
          content = androidStrings(json)
          path = path_for_context_language(context, language)
          write(context, language, content, :singular)
        when "kotlin_strings"
          content = kotlinStrings(json, header)
          path = path_for_context_language(context, language)
          write(context, language, content, :singular)
        end
      end
    end

    # Copy items with replaced placeholders to context json
    #
    # @param items [JSON]
    # @param context String
    # @param contextJson JSON
    #
    def copyPlaceholderItems(items, context, contextJson)
      items.each { |item|
        term = item["term"]
        definition = item["definition"].gsub(/\$([a-z_]{3,})/) { |placeholder|
          definitionForPlaceholder(placeholder, contextJson) 
        }

        if !contextJson.find { |e| e["term"] == term }
          newItem = {
            "term" => term,
            "definition" => definition,
            "context" => context
          }
          contextJson << newItem
        end
      }
    end

    def definitionForPlaceholder(placeholder, contextJson)
      term = placeholder.delete_prefix("$")
      contextJson.each { |item|
        if item["term"] == term
          return item["definition"]
        end
      }
      return placeholder
    end

    def singularAppleStrings(json)
      content = ""
      json.each { |item|
        term = item["term"]
        definition = item["definition"]
        if definition.instance_of? String
          value = definition.gsub("\"", "\\\"")
          content << "\"#{term}\" = \"#{value}\";\n"
        end
      }
      return content
    end

    def pluralAppleStrings(json)
      content = "
<?xml version=\"1.0\" encoding=\"UTF-8\"?>
<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">
<plist version=\"1.0\">
<dict>"
      json.each { |item|
        term = item["term"]
        definition = item["definition"]
        if definition.instance_of? Hash
          content << "
    <key>#{term}</key>
    <dict>
        <key>NSStringLocalizedFormatKey</key>
        <string>%\#@VARIABLE@</string>
        <key>VARIABLE</key>
        <dict>
            <key>NSStringFormatSpecTypeKey</key>
            <string>NSStringPluralRuleType</string>
            <key>NSStringFormatValueTypeKey</key>
            <string>d</string>"
          ["zero", "one", "two", "few", "many", "other"].each { |form|
            if definition[form] != nil
              value = definition[form].gsub("\"", "\\\"")
              content << "
            <key>#{form}</key>
            <string>#{value}</string>"
            else
              content << "
            <key>#{form}</key>
            <string></string>"
            end
          }
          content << "
        </dict>
    </dict>"
        end
      }
      content << "
</dict>
</plist>"
      return content
    end

    def androidStrings(json)
      content = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n<resources>\n"
      json.each { |item|
        definition = item["definition"]
        if definition != nil
          if definition.instance_of? String
            value = definition.gsub("\"", "\\\"").gsub("&", "&amp;")
            content << "    <string name=\"#{item["term"]}\">\"#{value}\"</string>\n"
          else	
            content << "    <plurals name=\"#{item["term"]}\">\n"
            ["zero", "one", "two", "few", "many", "other"].each { |form|
              pluralItem = androidPluralItem(definition, form)
              if pluralItem != nil
                content << pluralItem
              end
            }
            content << "    </plurals>\n"
          end
        end
      }
      content << "</resources>\n"
      return content
    end
    
    def kotlinStrings(json, header)
      content = ""
      if header != nil
      	content << "#{header}\n"
      end
      content << "
class Strings {
	companion object {
		val Strings by lazy {
			Strings()
		}
	}\n
"
      json.each { |item|
      	content << "    val #{snakeCaseToCamelCase(item["term"])} = \"#{item["term"]}\".localized()\n"
      }
      content << "}\n"
      return content
    end
    
    def snakeCaseToCamelCase(text)
    	words = text.split('_')
    	return words[0] + words[1..-1].collect(&:capitalize).join
    end

    def androidPluralItem(definition, form)
      if definition[form] != nil 
        value = definition[form].gsub("\"", "\\\"").gsub("&", "&amp;")
        return "    <item quantity=\"#{form}\">\"#{value}\"</item>\n"
      else
        return nil
      end
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

    def write(context, language, content, plurality)
      write_content_to_path(context, language, content, plurality)
      for alias_to, alias_from in @configuration.language_alias
        if language == alias_from
          write_content_to_path(context, alias_to, content, plurality)
        end
      end
    end

    # Write translation file
    def write_content_to_path(context, language, content, plurality)
      case plurality
      when :singular
        path = path_for_context_language(context, language)
      when :plural
        path = path_plural_for_context_language(context, language)
      end

      unless path != nil
        raise POEditor::Exception.new "Undefined context path"
      end

      if File.exist?(path)
        File.write(path, content)
        UI.puts "      #{"\xe2\x9c\x93".green} Saved at '#{path}'"
      else
        UI.puts "      #{"\xe2\x9c\x97".red} File not found '#{path}'"
      end
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

    def path_plural_for_context_language(context, language)
      if context == nil || context == ""
        path = @configuration.path_plural.gsub("{LANGUAGE}", language)
      else
        if @configuration.context_path_plural
          path = @configuration.context_path_plural.gsub("{LANGUAGE}", language).gsub("{CONTEXT}", context)
        else
          return nil
        end
      end
    end
  end
end

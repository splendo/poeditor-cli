module POEditor
  class Configuration
    # @return [String] POEditor API key
    # @see https://poeditor.com/account/api POEditor API Access
    attr_accessor :api_key

    # @return [String] POEditor project ID
    attr_accessor :project_id

    # @return [String] Export file type (po, apple_strings, android_strings)
    attr_accessor :type

    # @return [Array<String>] Tag filters (optional)
    attr_accessor :tags
    
    # @return [Array<String>] Filters by 'translated', 'untranslated', 'fuzzy', 'not_fuzzy', 'automatic', 'not_automatic', 'proofread', 'not_proofread' (optional)
    attr_accessor :filters

    # @return [Array<String>] The languages codes
    attr_accessor :languages

    # @return [Hash{Sting => String}] The languages aliases
    attr_accessor :language_alias

    # @return [String] The path template
    attr_accessor :path

    # @return [String] The plural path template
    attr_accessor :path_plural

    # @return [Hash{Sting => String}] The path replacements
    attr_accessor :path_replace

    # @return [String] The context path template
    attr_accessor :context_path

    # @return [String] The plural context path template
    attr_accessor :context_path_plural

    # @return [Hash{Sting => String}] The context path replacements
    attr_accessor :context_path_replace

    def initialize(api_key:, project_id:, type:, tags:nil, 
                   filters:nil, languages:, language_alias:nil,
                   path:, path_plural: nil, path_replace:nil,
                   context_path:nil, context_path_plural:nil, context_path_replace:nil)
      @api_key = from_env(api_key)
      @project_id = from_env(project_id.to_s)
      @type = type
      @tags = tags || []
      @filters = filters || []

      @languages = languages
      @language_alias = language_alias || {}

      @path = path
      @path_plural = path_plural || {}
      @path_replace = path_replace || {}

      @context_path = context_path
      @context_path_plural = context_path_plural || {}
      @context_path_replace = context_path_replace || {}
    end

    def from_env(value)
      if value.start_with?("$")
        key = value[1..-1]
        ENV[key]
      else
        value
      end
    end

    def to_s
      values = {
        "type" => self.type,
        "tags" => self.tags,
        "filters" => self.filters,
        "languages" => self.languages,
        "language_alias" => self.language_alias,
        "path" => self.path,
        "path_plural" => self.path_plaural,
        "path_replace" => self.path_replace,
        "context_path" => self.context_path,
        "context_path_plural" => self.context_path_plural,
        "context_path_replace" => self.context_path_replace,
      }
      YAML.dump(values)[4..-2]
        .each_line
        .map { |line|
          if line.start_with?("-") or line.start_with?(" ")
            "    #{line}"
          else
            "  - #{line}"
          end
        }
        .join("")
    end
  end
end

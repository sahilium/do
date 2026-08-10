module Do
  # Top-level error for all normal user-facing failures.
  class Error < StandardError
  end

  class ValidationError < Error
    attr_reader :errors

    def initialize(errors)
      @errors = Array(errors)
      super(@errors.join("\n"))
    end
  end
end
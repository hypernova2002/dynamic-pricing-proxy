# The gem is only installed in development and test, because docs are generated from specs.
if defined?(OpenapiRuby)
  OpenapiRuby.configure do |config|
    config.schemas = {
      public_api: {
        info: {
          title: "Dynamic Pricing Proxy API",
          version: "v1",
          description: "Serves hotel room rates, cached for at most five minutes from the dynamic pricing model."
        },
        servers: [ { url: "/" } ]
      }
    }

    config.component_paths = [ "spec/api_components" ]
    config.camelize_keys = false
    config.schema_output_dir = "openapi"
    config.schema_output_format = :yaml
    # Otherwise the gem documents a 400 response, which this API never returns.
    config.auto_validation_error_response = false
  end
end

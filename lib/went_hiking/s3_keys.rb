# frozen_string_literal: true

module WentHiking
  module S3Keys
    module_function

    def legacy_system_key(path)
      path.to_s.sub(%r{\A/+}, "").sub(%r{\Apublic/}, "")
    end

    def photo_variant_key(photo_id:, style:, filename:)
      "system/images/#{photo_id}/#{style}/#{filename}"
    end

    def avatar_variant_key(account_id:, style:, filename:)
      "system/avatars/#{account_id}/#{style}/#{filename}"
    end

    def upload_original_key(account_id:, photo_id:, filename:)
      clean = filename.to_s.gsub(%r{[^A-Za-z0-9._-]+}, "-")
      "uploads/photos/#{account_id}/#{photo_id}/original/#{clean}"
    end
  end
end

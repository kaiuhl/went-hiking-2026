# frozen_string_literal: true

require "went_hiking/local_upload_token"
require "went_hiking/storage"

# Receiving end of Storage::Local#direct_upload_post.
#
# Authorization is the signed token in the multipart body, not the session, which
# mirrors how an S3 presigned POST works. That is also why this route is exempt
# from CSRF: there is no ambient authority to abuse, and the browser sends the
# same multipart body it would send to S3.
module UploadRoutes
  def route_uploads(r)
    r.post "uploads", "direct" do
      storage = local_upload_storage
      not_found unless storage

      ticket = WentHiking::LocalUploadToken.verify(request.POST)
      halt_upload_error(ticket.error, 403) unless ticket.valid?

      file = request.POST["file"]
      tempfile = file.is_a?(Hash) ? file[:tempfile] : nil
      halt_upload_error("Choose a photo to upload.", 400) unless tempfile

      size = tempfile.size
      halt_upload_error("Image file is too small.", 422) if size < ticket.min_bytes
      halt_upload_error("Image file is too large.", 422) if size > ticket.max_bytes

      declared_type = file[:type].to_s
      unless declared_type.empty? || declared_type == ticket.content_type
        halt_upload_error("Image type does not match the upload ticket.", 422)
      end

      storage.put(ticket.key, io: tempfile, content_type: ticket.content_type)

      response.status = 201
      response["Content-Type"] = "text/plain"
      ""
    end
  end

  private

  def local_upload_storage
    storage = WentHiking::Storage.current
    storage.local? ? storage : nil
  rescue
    nil
  end

  def halt_upload_error(message, status)
    request.halt [status, {"Content-Type" => "application/json"}, [JSON.generate({errors: [message]})]]
  end
end

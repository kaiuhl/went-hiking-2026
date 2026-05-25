# frozen_string_literal: true

require "cgi"
require "premailer"

module WentHiking
  class EmailRenderer
    TEMPLATE_BY_SUBJECT = {
      "Verify Account" => {
        subject: "Verify your Went Hiking account",
        headline: "Ready to join the trail log?",
        intro: "Thanks for creating a Went Hiking account. Verify your email and you can start logging trips, sharing photos, and finding the next place to go.",
        cta_label: "Verify account",
        outro: "If you did not create this account, you can ignore this email."
      },
      "Reset Password" => {
        subject: "Reset your Went Hiking password",
        headline: "Reset your password",
        intro: "Use this link to choose a new password for your Went Hiking account.",
        cta_label: "Reset password",
        outro: "If you did not request a password reset, you can ignore this email."
      },
      "Unlock Account" => {
        subject: "Unlock your Went Hiking account",
        headline: "Unlock your account",
        intro: "Your account is locked for now. Use this link to unlock it and get back to your trips.",
        cta_label: "Unlock account",
        outro: "If you did not request this unlock, you can ignore this email."
      }
    }.freeze

    URL_PATTERN = %r{https?://[^\s<>"]+}

    def initialize(public_base_url: WentHiking.public_base_url)
      @public_base_url = public_base_url.to_s.sub(%r{/+\z}, "")
    end

    def render(to:, subject:, body:)
      template = TEMPLATE_BY_SUBJECT[subject.to_s]
      cta_url = extract_url(body)
      subject_line = template ? template.fetch(:subject) : subject.to_s
      cta_label = if template
        template.fetch(:cta_label)
      elsif cta_url
        "Open link"
      end

      text_body = if template
        template_text(template, cta_url)
      else
        fallback_text(body)
      end

      html_body = template_html(
        subject: subject_line,
        headline: template&.fetch(:headline, nil) || subject_line,
        intro: template&.fetch(:intro, nil) || fallback_text(body),
        outro: template&.fetch(:outro, nil),
        cta_label: cta_label,
        cta_url: cta_url
      )

      {
        to: to,
        subject: subject_line,
        text_body: text_body,
        html_body: html_body,
        cta_label: cta_label,
        cta_url: cta_url
      }
    end

    def render_template(to:, subject:, headline:, intro:, cta_label: nil, cta_url: nil, outro: nil, unsubscribe_url: nil)
      text_body = template_text(
        {
          headline: headline,
          intro: intro,
          cta_label: cta_label,
          outro: outro
        },
        cta_url,
        unsubscribe_url: unsubscribe_url
      )

      html_body = template_html(
        subject: subject,
        headline: headline,
        intro: intro,
        outro: outro,
        cta_label: cta_label,
        cta_url: cta_url,
        unsubscribe_url: unsubscribe_url
      )

      {
        to: to,
        subject: subject,
        text_body: text_body,
        html_body: html_body,
        cta_label: cta_label,
        cta_url: cta_url
      }
    end

    private

    attr_reader :public_base_url

    def extract_url(body)
      body.to_s[URL_PATTERN]&.sub(/[.)\]]+\z/, "")
    end

    def template_text(template, cta_url, unsubscribe_url: nil)
      lines = [
        template.fetch(:headline),
        "",
        template.fetch(:intro),
        ""
      ]

      if cta_url
        lines.concat([
          "#{template.fetch(:cta_label)}: #{cta_url}",
          "",
          "If the button does not work, copy and paste the link into your browser:",
          cta_url,
          ""
        ])
      end

      outro = template[:outro]
      lines.concat([outro, ""]) if outro && !outro.to_s.empty?
      lines.concat(["Unsubscribe: #{unsubscribe_url}", ""]) if unsubscribe_url
      lines.concat(["Happy trails,", "Went Hiking"])

      lines.join("\n")
    end

    def fallback_text(body)
      body.to_s.gsub(/\r\n?/, "\n").lines.map(&:strip).reject(&:empty?).join("\n\n")
    end

    def template_html(subject:, headline:, intro:, outro:, cta_label:, cta_url:, unsubscribe_url: nil)
      html = <<~HTML
        <!doctype html>
        <html>
          <head>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width, initial-scale=1">
            <title>#{h(subject)}</title>
            <style>
              body { margin: 0; padding: 0; background: #f4f3ee; color: #242420; font-family: Arial, Helvetica, sans-serif; }
              table { border-collapse: collapse; }
              img { border: 0; display: block; }
              .preheader { display: none; max-height: 0; overflow: hidden; opacity: 0; color: transparent; }
              .page { width: 100%; background: #f4f3ee; }
              .container { width: 100%; max-width: 600px; margin: 0 auto; }
              .card { background: #fffdf7; border: 1px solid #dedbd1; }
              .header { padding: 34px 36px 16px; text-align: center; }
              .content { padding: 20px 36px 34px; }
              .headline { margin: 0 0 16px; color: #111; font-size: 30px; line-height: 1.15; font-weight: 700; }
              .body-copy { margin: 0 0 22px; color: #34342f; font-size: 16px; line-height: 1.55; }
              .button-cell { background: #111; }
              .button-link { display: inline-block; padding: 14px 22px; color: #fffdf7; font-size: 15px; font-weight: 700; text-decoration: none; }
              .url-help { margin: 22px 0 0; color: #68675f; font-size: 13px; line-height: 1.5; }
              .url-help a { color: #242420; word-break: break-all; }
              .footer { padding: 20px 36px 34px; color: #77756c; font-size: 12px; line-height: 1.5; text-align: center; }
            </style>
          </head>
          <body>
            <div class="preheader">#{h(intro.to_s)}</div>
            <table role="presentation" class="page" width="100%" cellpadding="0" cellspacing="0">
              <tr>
                <td align="center" style="padding: 28px 12px;">
                  <table role="presentation" class="container" width="600" cellpadding="0" cellspacing="0">
                    <tr>
                      <td class="card">
                        <table role="presentation" width="100%" cellpadding="0" cellspacing="0">
                          <tr>
                            <td class="header" align="center">
                              <img src="#{h(logo_url)}" width="180" height="61" alt="Went Hiking">
                            </td>
                          </tr>
                          <tr>
                            <td class="content">
                              <h1 class="headline">#{h(headline)}</h1>
                              #{paragraphs(intro)}
                              #{cta_button(cta_label, cta_url)}
                              #{url_fallback(cta_url)}
                              #{paragraphs(outro)}
                              #{unsubscribe_block(unsubscribe_url)}
                            </td>
                          </tr>
                          <tr>
                            <td class="footer">
                              Happy trails,<br>
                              Went Hiking<br>
                              <a href="#{h(public_base_url)}" style="color: #242420;">#{h(public_base_url)}</a>
                            </td>
                          </tr>
                        </table>
                      </td>
                    </tr>
                  </table>
                </td>
              </tr>
            </table>
          </body>
        </html>
      HTML

      Premailer.new(html, with_html_string: true).to_inline_css.gsub(%r{<style[^>]*>.*?</style>}mi, "")
    end

    def paragraphs(value)
      fallback_text(value).split("\n\n").map do |paragraph|
        %(<p class="body-copy">#{h(paragraph)}</p>)
      end.join
    end

    def cta_button(label, url)
      return "" unless label && url

      <<~HTML
        <table role="presentation" cellpadding="0" cellspacing="0">
          <tr>
            <td class="button-cell">
              <a class="button-link" href="#{h(url)}">#{h(label)}</a>
            </td>
          </tr>
        </table>
      HTML
    end

    def url_fallback(url)
      return "" unless url

      <<~HTML
        <p class="url-help">If the button does not work, copy and paste this link:<br>
          <a href="#{h(url)}">#{h(url)}</a>
        </p>
      HTML
    end

    def unsubscribe_block(url)
      return "" unless url

      <<~HTML
        <p class="url-help">You can <a href="#{h(url)}">unsubscribe from these hike emails</a> any time.</p>
      HTML
    end

    def logo_url
      "#{public_base_url}/images/email-wordmark.png"
    end

    def h(value)
      CGI.escape_html(value.to_s)
    end
  end
end


# This is a copy of the RACK Utils code, I couldn't use it since I have an old
# copy of rack bundled with RQ
#

module RQ
  class HtmlUtils

    ESCAPE_HTML = {
      "&" => "&amp;",
      "<" => "&lt;",
      ">" => "&gt;",
    }
    ESCAPE_HTML_PATTERN = Regexp.union(*ESCAPE_HTML.keys)

    def self.escape_html(text)
      text.gsub(ESCAPE_HTML_PATTERN){|c| ESCAPE_HTML[c] }
    end

    def self.linkify_text(text)
      text.gsub(/(https?:\/\/[^\s]+)/) { |m| "<a href='#{m}'>#{m}</a>" }
    end

    def self.ansi_to_html(text)
      terminal = AnsiUtils.new
      terminal.process_text(text)
    end

  end

  class AnsiUtils

    # Normal and then Bright
    ANSI_COLORS = [
      ["0,0,0", "187, 0, 0", "0, 187, 0", "187, 187, 0", "0, 0, 187", "187, 0, 187", "0, 187, 187", "255,255,255" ],
      ["85,85,85", "255, 85, 85", "0, 255, 0", "255, 255, 85", "85, 85, 255", "255, 85, 255", "85, 255, 255", "255,255,255" ],
    ]

    attr_accessor :fore
    attr_accessor :back

    def initialize
      @fore = @back = nil
      @bright = 0
    end

    def process_text(text)
      data4 = text.split(/\033\[/)

      first = data4.shift # the first chunk is not the result of the split

      data5 = data4.map { |chunk| process_chunk(chunk) }

      data5.unshift(first)

      escaped_data = data5.flatten.join('')
    end

    def process_chunk(text)
      # Do proper handling of sequences (aka - injest vi split(';') into state machine
      match,codes,txt = *text.match(/([\d;]+)m(.*)/m)

      if not match
        return txt
      end

      nums = codes.split(';')

      nums.each do
        |num_str|

        num = num_str.to_i

        if num == 0
          @fore = @back = nil
          @bright = 0
        elsif num == 1
          @bright = 1
        elsif (num >= 30) and (num < 38)
          @fore = "rgb(#{ANSI_COLORS[@bright][(num % 10)]})"
        elsif (num >= 40) and (num < 48)
          @back = "rgb(#{ANSI_COLORS[0][(num % 10)]})"
        end
      end

      if (@fore == nil) && (@back == nil)
        txt
      else
        style = []
        style << "color:#{@fore}" if @fore
        style << "background-color:#{@back}" if @back
        ["<span style='#{style.join(';')}'>", txt, "</span>"]
      end
    end

  end
end


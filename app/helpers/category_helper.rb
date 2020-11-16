require 'open-uri'
require 'nokogiri'

module CategoryHelper
  J_ARCHIVE_SEARCH = "https://j-archive.com/search.php?search="
  J_ARCHIVE_GAME   = "https://j-archive.com/showgame.php?game_id="

  # retrieve j-archive show id for the given date in YYYY-MM-DD format
  def get_jarchive_game_id(dt)
    content = URI.open(J_ARCHIVE_SEARCH + dt).read
    return if content.nil?

    document = Nokogiri::HTML.parse(content)
    games = {}
    document.xpath('//div[@id="content"]//td/a').each { |link|
      if link[:href].match(/showgame.php\?.*game_id=(\d+)/)
        game_id = $1
        if link.text.match(/#\d+, aired (\d+-\d+-\d+)/)
          games[$1] = game_id
        end
      end
    }

    games[dt]
  end

  # parse out categories for the specified round
  def categories(document, round)
    document.xpath('//div[@id="' + round + '"]//td[@class="category_name"]/text()').map { |el|
      el.content
    }
  end

  # retrieve categories for the given game-id
  def get_jarchive_game_categories(game_id)
    content = URI.open(J_ARCHIVE_GAME + game_id).read
    return if content.nil?

    document = Nokogiri::HTML.parse(content)
    return {
      :round_1 => categories(document, "jeopardy_round"),
      :round_2 => categories(document, "double_jeopardy_round"),
      :final   => categories(document, "final_jeopardy_round")
    }
  end

  # retrieve categories for a show given the air-date in YYYY-MM-DD format
  def get_jarchive_game_categories_by_airdate(dt)
    return if dt.nil?
    game_id = get_jarchive_game_id(dt)

    return if game_id.nil?
    get_jarchive_game_categories(game_id)
  end
end

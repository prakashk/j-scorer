# rubocop:disable ClassLength
class TopicsSummary
  include SharedStatsMethods

  attr_reader :stats

  def initialize(user, play_types, filters)
    query = topics_query(user, play_types, coalesce_filters(filters))
    delete_orphaned_topics(user)
    @stats = ActiveRecord::Base.connection.select_all(query).to_a
  end

  private

  def delete_orphaned_topics(user)
    deletion_sql = "
    DELETE FROM topics WHERE id IN (
      SELECT t.id
      FROM topics t
      LEFT JOIN category_topics ct ON ct.topic_id = t.id
      WHERE user_id = #{user.id}
      GROUP BY t.id
      HAVING count(ct.id) = 0
    )"
    ActiveRecord::Base.connection.execute(deletion_sql)
  end

  # rubocop:disable MethodLength
  def topics_query(user, play_types, other_filters)
    validate_query_inputs(user, play_types)
    play_types_list = format_play_types_for_sql(play_types)
    "
    SELECT
      *,
      (
        CASE
          WHEN o.possible_score > 0
            THEN (1.0 * o.score / o.possible_score)
        END
      ) AS efficiency,
      (
        CASE
          WHEN o.dds > 0
            THEN (1.0 * o.dd_right / o.dds)
        END
      ) AS dd_rate,
      (
        CASE
          WHEN o.finals_count > 0
            THEN (1.0 * o.finals_right / o.finals_count)
        END
      ) AS final_rate,
      (
        CASE
          WHEN o.final_onair_den > 0
            THEN (1.0 * o.final_onair_right / o.final_onair_den)
        END
      ) AS final_onair_rate
    FROM (
      SELECT
        q.topic_name,
        COUNT(*) FILTER (WHERE q.sixth_type IS NOT NULL) AS sixths_count,
        SUM(q.right) AS right,
        SUM(q.wrong) AS wrong,
        SUM(q.pass) AS pass,
        SUM(q.score) AS score,
        SUM(q.possible_score) AS possible_score,
        SUM(q.dd_right) + SUM(q.dd_wrong) AS dds,
        SUM(q.dd_right) AS dd_right,
        SUM(q.dd_wrong) AS dd_wrong,
        SUM(q.final_right) + SUM(q.final_wrong) AS finals_count,
        SUM(q.final_right) AS finals_right,
        SUM(q.final_wrong) AS finals_wrong,
        SUM(q.final_onair_right) + SUM(q.final_onair_wrong) AS final_onair_den,
        SUM(q.final_onair_right) AS final_onair_right
      FROM (
        SELECT
          i.topic_name,
          i.sixth_type,
          #{result_count('i', 3)} AS right,
          #{result_count('i', 1)} AS wrong,
          #{result_count('i', 2)} AS pass,
          (
            (#{result_count('i', [3, 7], true)}) -
            (#{result_count('i', 1, true)})
          ) * i.top_row_value AS score,
          (
            #{result_count('i', [1, 2, 3, 5, 6, 7], true)}
          ) * i.top_row_value AS possible_score,
          #{result_count('i', 7)} AS dd_right,
          #{result_count('i', [5, 6])} AS dd_wrong,
          CASE WHEN i.final_result = 3 THEN 1 ELSE 0 END AS final_right,
          CASE WHEN i.final_result = 1 THEN 1 ELSE 0 END AS final_wrong,
          i.final_onair_right,
          i.final_onair_wrong
        FROM (
          SELECT
            t.name AS topic_name,
            s.result1,
            s.result2,
            s.result3,
            s.result4,
            s.result5,
            s.type AS sixth_type,
            (
              CASE s.type
                WHEN 'RoundOneCategory' THEN #{CURRENT_TOP_ROW_VALUES[0]}
                WHEN 'RoundTwoCategory' THEN #{CURRENT_TOP_ROW_VALUES[1]}
              END
            ) AS top_row_value,
            f.result AS final_result,
            (
              CASE WHEN f.first_right THEN 1 ELSE 0 END +
              CASE WHEN f.second_right THEN 1 ELSE 0 END +
              CASE WHEN f.third_right THEN 1 ELSE 0 END
            ) AS final_onair_right,
            (
              CASE WHEN f.first_right IS FALSE THEN 1 ELSE 0 END +
              CASE WHEN f.second_right IS FALSE THEN 1 ELSE 0 END +
              CASE WHEN f.third_right IS FALSE THEN 1 ELSE 0 END
            ) AS final_onair_wrong
          FROM
            topics t
            INNER JOIN category_topics c
              ON t.id = c.topic_id
            LEFT JOIN sixths s
              ON c.category_id = s.id AND c.category_type = 'Sixth'
            LEFT JOIN finals f
              ON c.category_id = f.id AND c.category_type = 'Final'
            LEFT JOIN games gOne
              ON s.game_id = gOne.id
            LEFT JOIN games gTwo
              ON f.game_id = gTwo.id
          WHERE
            t.user_id = #{user.id}
            AND COALESCE(gOne.play_type, gTwo.play_type) IN (#{play_types_list})
            #{other_filters}
        ) i
      ) q
      GROUP BY topic_name
      ORDER BY topic_name
    ) o
    "
  end
  # rubocop:enable MethodLength
end
# rubocop:enable ClassLength

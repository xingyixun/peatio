class Global
  ZERO = '0.0'.to_d
  NOTHING_ARRAY = YAML::dump([])
  LIMIT = 80

  attr_accessor :currency

  def initialize(currency)
    @currency = currency
  end

  def order_asks
    @asks ||= OrderAsk.active.
      with_currency(currency).
      matching_rule.position
  end

  def order_bids
    @bids ||= OrderBid.active.
      with_currency(currency).
      matching_rule.position
  end

  def channel
    "market-#{@currency}-global"
  end

  def self.[](market)
    if market.is_a? Market
      self.new(market.id)
    else
      self.new(market)
    end
  end

  def key(key)
    "#{@currency}-#{key}"
  end

  def redis_client
    Rails.cache
  end

  def ticker
    redis_client.read(key('ticker')) || update_ticker
  end

  def trades
    redis_client.read(key('trades')) || update_trades
  end

  def since_trades(id)
    trades ||= Trade.with_currency(currency)
      .where("id > ?", id).order(:id).limit(LIMIT)
    trades.map {|t| format_trade(t)}
  end

  def market_data
    Rails.cache.fetch "market data #{Time.now.strftime('%F %R')}" do
      trades ||= Trade.with_currency(currency)
        .select("id, price, sum(volume) as volume, trend, currency, max(created_at) as created_at")
        .where("created_at > ?", 12.to_i.hours.ago).order(:id)
        .group("ROUND(UNIX_TIMESTAMP(created_at)/(15 * 60))") # per 15 minutes
        .order('max(created_at) ASC')
      trades.map {|t| format_trade(t)}
    end
  end

  def asks
    redis_client.read(key('asks')) || update_asks
  end

  def bids
    redis_client.read(key('bids')) || update_bids
  end

  def update_ticker
    Trade.with_currency(currency).tap do |query|
      redis_client.write key('ticker'), {
        :at => at,
        :low => query.h24.minimum(:price) || ZERO,
        :high => query.h24.maximum(:price) || ZERO,
        :last => query.last.try(:price) || ZERO,
        :volume => query.h24.sum(:volume) || ZERO,
        :buy => (bids.first && bids.first[0]) || ZERO,
        :sell => (asks.first && asks.first[0]) || ZERO
      }
    end
    ticker
  end

  def update_asks
    redis_client.write key('asks'), (order_asks || [])
    asks
  end

  def update_bids
    redis_client.write key('bids'), (order_bids || [])
    bids
  end

  def format_trade(t)
    ask_member_sn = Rails.cache.fetch "#{t.cache_key}_ask_member_sn" do
      t.ask_member_sn
    end

    bid_member_sn = Rails.cache.fetch "#{t.cache_key}_bid_member_sn" do
      t.bid_member_sn
    end

    { ask_member_sn: ask_member_sn,
      bid_member_sn: bid_member_sn,
      date:   t.created_at.to_i,
      price:  t.price.to_s  || ZERO,
      amount: t.volume.to_s || ZERO,
      tid:    t.id,
      type:   t.trend ? 'sell' : 'buy' }
  end

  def update_trades
    @trades ||= Trade.with_currency(currency).order(:id).reverse_order.last(LIMIT)
    @maped_trades = @trades.map {|t| format_trade(t)}
    redis_client.write key('trades'), (@maped_trades || [])
    trades
  end

  def trigger_trade(t)
    data = {:trades => [format_trade(t)]}
    Pusher.trigger_async(channel, "trades", data)
  end

  def trigger
    data = {:ticker => ticker, :asks => asks, :bids => bids}
    Pusher.trigger_async(channel, "update", data)
  end

  def at
    @at ||= DateTime.now.to_i
  end
end

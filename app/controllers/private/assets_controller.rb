module Private
  class AssetsController < BaseController
    before_action :auth_activated!

    def index
      @btc_addresses = Currency.addresses['btc']
      @btc_proof = Proof.with_currency(:btc).last
      @cny_proof = Proof.with_currency(:cny).last
      @btc_account = current_user.accounts.with_currency(:btc).first
      @cny_account = current_user.accounts.with_currency(:cny).first
    end

  end
end
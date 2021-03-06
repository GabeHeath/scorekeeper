class AutofillController < ApplicationController
  def bgg
    render json: Bgg.bgg_autofill_search(params[:term])
  end

  def location
    render json: Bgg.autofill_locations_and_players(params[:term], current_user.plays, 'location')
  end

  def player
    render json: Bgg.autofill_locations_and_players(params[:term], current_user.friends, 'name')
  end

  def game
    render json: Bgg.autofill_play_games_name(current_user, params[:term])
  end
end
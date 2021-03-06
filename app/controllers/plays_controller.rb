class PlaysController < ApplicationController
  before_action :set_play, only: [:show, :edit, :update, :destroy]

  # GET /plays
  # GET /plays.json
  def index

    if params[:per_page]
      @per_page = params[:per_page]
    else
      @per_page = 10
    end

    unless (params[:friend_name]).blank?
      @friend_plays = Play.with_friend(current_user, params[:friend_name])
      @search = @friend_plays.ransack(params[:q])
    else
      @search = current_user.plays.ransack(params[:q])
    end

    @plays = @search.result.paginate(:page => params[:page], :per_page => @per_page).order('date DESC')
  end

  # GET /plays/1
  # GET /plays/1.json
  def show
    @plays = current_user.plays
    if user_signed_in?
      unless @play.user_ids.include? current_user.id
        flash[:error] = "The page you requested does not exist."
        redirect_to plays_url
        return
      end
    else
      flash[:error] = "Please log in."
      redirect_to root_path
      return
    end
  end

  # GET /plays/new
  def new
    @play = Play.new
  end

  # GET /plays/1/edit
  def edit
  end

  # POST /plays
  # POST /plays.json
  def create

    @play = Play.new(play_params)
    @play.created_by = current_user.id

    @game = Game.new(game_params)
    # Parse and set game_id
    data = Bgg.bgg_get_name_and_id((@game.name).to_s) #Returns array of 2 if name user typed doesn't exist or api failed. Returns 3 if found in BGG database.
    attributes = {name: data[0], year: data[1], bgg_id: data[2]}
    @new_game = Game.where(attributes).first_or_create

    @play.game_id = @new_game.id


    respond_to do |format|
      if @play.save
        if params[:name].nil?
          name = [current_user.name]
        else
          name = params[:name].unshift(current_user.name)
        end

        name.each_with_index do |name, index|
          @player = Player.new

          if index == 0
            @player.user_id = current_user.id
            @play.create_activity :create, owner: current_user
          else
            friend_user_id = get_friend_user_id(name, current_user.friends)
            if friend_user_id
              @player.user_id = friend_user_id
              @play.create_activity :create, owner: User.find(friend_user_id)

              @notification = Notification.new
              @notification.user_id = friend_user_id
              @notification.notifier_id = current_user.id
              @notification.key = 'play.included'
              @notification.trackable_id = @play.id
              @notification.save
            else
              @player.non_friend_name = name
            end
          end
          @player.play_id = @play.id
          @player.score = params[:score][index]
          @player.win = params[:win][index]
          @player.team = params[:team][index]
          @player.save

        end


        expansions = params[:expansion]
        expansions.each_with_index do |expansion, index|
          unless expansion.blank?
            @expansion = Expansion.new

            data = Bgg.bgg_get_name_and_id(expansions[index])
            attributes = {name: data[0], year: data[1], bgg_id: data[2]}
            @new_expansion = Expansion.where(attributes).first_or_create

            @play_expansion = PlayExpansion.new

            @play_expansion.play_id = @play.id
            @play_expansion.expansion_id = @new_expansion.id
            @play_expansion.save
          end
        end


        if @player.save
          format.html { redirect_to @play, notice: 'Play was successfully created.' }
          format.json { render :show, status: :created, location: @play }
        else
          format.html { render :new }
          format.json { render json: @play.errors, status: :unprocessable_entity }
        end
      else
        format.html { render :new }
        format.json { render json: @play.errors, status: :unprocessable_entity }
      end
    end
  end

  # PATCH/PUT /plays/1
  # PATCH/PUT /plays/1.json
  def update
    @play = Play.find(params[:id])

    # UPDATE GAME NAME
        @game = Game.new(game_params)
        # Parse and set game_id
        data = Bgg.bgg_get_name_and_id((@game.name).to_s) #Returns array of 2 if name user typed doesn't exist or api failed. Returns 3 if found in BGG database.
        attributes = {name: data[0], year: data[1], bgg_id: data[2]}
        @new_game = Game.where(attributes).first_or_create

        @play.game_id = @new_game.id


    # UPDATE EXISTING PLAYERS
        (params[:pid]).each_with_index do |player_id, index|
          @player = @play.players.find_by_id(player_id)

          if params[:existing_delete][index] == "1"
            @player.destroy
          else
            @player.score = params[:existing_score][index]
            @player.team = params[:existing_team][index]
            @player.win = params[:existing_win][index]
            @player.save

            unless @player.user_id.blank? || @player.user_id == current_user.id
              @notification = Notification.new
              @notification.user_id = @player.user_id
              @notification.notifier_id = current_user.id
              @notification.key = 'play.edited'
              @notification.trackable_id = @play.id
              @notification.save
            end
          end
        end

    # SAVE NEW PLAYERS

        unless params[:name].nil?
          params[:name].each_with_index do |name, index|
            @new_player = Player.new

            unless name.blank?
              friend_user_id = get_friend_user_id(name, current_user.friends)
              if friend_user_id
                @new_player.user_id = friend_user_id

                @notification = Notification.new
                @notification.user_id = friend_user_id
                @notification.notifier_id = current_user.id
                @notification.key = 'play.included'
                @notification.trackable_id = @play.id
                @notification.save
              else
                @new_player.non_friend_name = name
              end

              @new_player.play_id = @play.id
              @new_player.score = params[:score][index]
              @new_player.win = params[:win][index]
              @new_player.team = params[:team][index]
              @new_player.save
            end
          end
        end

    #UPDATE EXISTING EXPANSIONS
      unless params[:eid].nil?
        (params[:eid]).each_with_index do |play_expansion_id, index|
          @play_expansion = @play.play_expansions.find_by_id(play_expansion_id)

          if params[:expansion_delete][index] == "1"
            @play_expansion.destroy
          end
        end
      end


    # SAVE NEW EXPANSIONS
        expansions = params[:expansion]

        unless expansions.nil?
          expansions.each_with_index do |expansion, index|
            unless expansion.blank?
              @expansion = Expansion.new

              data = Bgg.bgg_get_name_and_id(expansions[index])
              attributes = {name: data[0], year: data[1], bgg_id: data[2]}
              @new_expansion = Expansion.where(attributes).first_or_create

              @play_expansion = PlayExpansion.new

              @play_expansion.play_id = @play.id
              @play_expansion.expansion_id = @new_expansion.id
              @play_expansion.save
            end
          end
        end

    respond_to do |format|
      if @play.update(play_params)
        @play.create_activity :update, owner: current_user
        format.html { redirect_to @play, notice: 'Play was successfully updated.' }
        format.json { render :show, status: :ok, location: @play }
      else
        format.html { render :edit }
        format.json { render json: @play.errors, status: :unprocessable_entity }
      end
    end
  end

  # DELETE /plays/1
  # DELETE /plays/1.json
  def destroy
    @play.destroy

    @activity = PublicActivity::Activity.where(trackable_id: (params[:id]), trackable_type: controller_path.classify)
    @activity.each do |activity|
      activity.destroy
    end

    respond_to do |format|
      format.html { redirect_to plays_url, notice: 'Play was successfully destroyed.' }
      format.json { head :no_content }
    end
  end

  private
  # Use callbacks to share common setup or constraints between actions.
  def set_play
    @play = Play.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def play_params
    params.require(:play).permit(:game_id, :date, :location, :notes, :created_at)
  end

  def game_params
    params.require(:game).permit(:name, :year, :bgg_id, :game_type)
  end

  def player_params
    params.require(:player).permit(:score, :win, :_destroy) #:play_id, :user_id, :score, :win,
  end

  def get_friend_user_id(player_name, users_friends)
    users_friends.each do |friend|
      if friend.name == player_name
        return friend.id
      end
    end
    return
  end

end

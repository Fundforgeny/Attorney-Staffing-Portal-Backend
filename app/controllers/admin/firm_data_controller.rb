class Admin::FirmDataController < ApplicationController
  # Public Custom Actions

  def index
		render json: { ok: true }
	end
end

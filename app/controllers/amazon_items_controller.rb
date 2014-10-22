require 'amazon1.rb'
class AmazonItemsController < ApplicationController
	def initialize
		super
		@amazon = Amazon.new
	end
  def home
  end

  def search
		@item_page = @amazon.item_page.get(params[:q])
		@item = @item_page.item
  end
end

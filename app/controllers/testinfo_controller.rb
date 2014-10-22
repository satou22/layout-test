class TestinfoController < ApplicationController
	def initialize
		super
		@a = Mechanize.new.set
	end
  def home
		@page = @a.get("http://taruo.net/e/")
  end
end

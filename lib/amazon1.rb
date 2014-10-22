#!ruby -Ku
base = File.dirname(__FILE__)
require 'rubygems'
require 'open-uri'
require "#{base}/lib.rb"
require 'time'
require 'date'
require "json"
require "selenium-webdriver"
require "mechanize"

class Mechanize
	def parse_html(data, uri="http://www.example.com")
		uri = URI.parse(uri) unless uri.is_a?(URI)
		page = Mechanize::Page.new( uri, {'content-type' => 'text/html'}, data, "200", self)
		self.history.push(page)
		page
	end
end

def get_model(title)
	title =~ /(\w*[\-].*?)([^\w^\/^\-]|\Z)/
	ret = $1.to_s
	return ret if ret.match(/\d/) && ret.match(/\w/) if ret
	nil
end

def img_save(img_uri, save_file)
	img_path = Addressable::URI.parse(img_uri)
	puts "SAVE_IMG:#{save_file}"
	open(save_file, "wb") {|w|
		open(img_path) {|data|
			w.write(data.read)
		}
	}
end

class Amazon
	attr_reader :item_page, :search_page, :region

	def self.get_asin(region, asin)
		begin
			@@amazon_agent.get("http://www.amazon.#{region}/dp/#{asin}")
		rescue => ex
			return nil
		end

		return @@amazon_agent.page.uri
	end

	def self.base_url(url)
		url.split(/(http:\/\/.*?)\//)[1]
	end

	def initialize(region = "co.jp")
		@@base_url = 'http://www.amazon.co.jp/' unless region
		@@base_url = "http://www.amazon.#{region}/" if region
		@@region = region
		@@amazon_agent = Mechanize.new.set
		@item_page = ItemPage.new
		@search_page = SearchPage.new
		self
	end

	def search(uri_or_word, category = nil)
		@search_page.get(uri_or_word, category)
	end
end

class Amazon::Util
	class << self
		def get_asin(url)
			url.strip!
			url += "/" unless url[url.length-1] == "/"
			return $2 if url =~ /\/(dp|product|offer-listing)\/(\w{10,10})\// 
		end
	end
end

class Amazon::ItemPage < Amazon
	
	attr_reader :agent, :adult, :item
	attr_reader :main_img_src, :sub_img_src, :img_src
	attr_accessor :uri

	def initialize()
		@@agent = Mechanize.new.set
	  @@agent.redirection_limit=3
	end

	def get(asin_or_uri, region = "co.jp")
		@item = Item.new
		if region && asin_or_uri =~ /^http.*/
			asin_or_uri = "http://www.amazon.#{region}/dp/#{asin(asin_or_uri)}"
		elsif region
			asin_or_uri = "http://www.amazon.#{region}/dp/#{asin_or_uri}"
		end
		@@agent.get(asin_or_uri)
		@uri = @@agent.page.uri

		@adult = false
		if @@agent.page.title =~ /アダルトコンテンツ/ 
			@@agent.page.link_with(text: '［はい］').click
			@adult = true
		elsif @@agent.page.at("#adultWarning") 
				@adult = true
		end
		@item.set
		@sub_img_src = set_sub_img_src
		@main_img_src = set_main_img_src
		@img_src = set_img_src
		self
	end

	def empty?
		@@agent.page ? false : true
	end
	def agent
		@@agent
	end
	def page
		@@agent.page
	end

	def asin(uri=nil)
		uri ||= @@agent.page.uri.to_s
		uri.strip!
		uri += "/" unless uri[uri.length-1] == "/"
		return $2 if uri =~ /\/(dp|product|offer-listing)\/(.+?)\// 
#     return $2 if uri =~ /\/(dp|product|offer-listing)\/(.+?)/ 
	end

	def short_uri
		"#{Amazon.base_url(@@agent.page.uri.to_s)}/dp/#{self.asin}"
	end

	def img_length()
		return @sub_img_src.length if @sub_img_src && @sub_img_src.length > 0
		return 1 if @main_img_src
		return 0
	end

	def img_save(save_path, size1 = nil, size2 = nil)
		if @img_src
			if @sub_img_src
				sub_img_save(save_path, size1, size2)
			else
				main_img_save(save_path, size1, size2)
			end
		end
	end
	private
		def set_img_src
			if img_src = @sub_img_src || @main_img_src
				img_src.map! {|src| src.gsub(/_.+_\./, "_SL500_AA500_.") }
			end
			img_src
		end
		def set_main_img_src
	#     main_img_src = @agent.page.search('.a-button-input')
	#      main_img_src = @agent.page.at('#IV-Main') 
			 main_img_src ||= @@agent.page.at('#prodImageContainer img')
			 main_img_src ||= @@agent.page.at('prodImageCell img')
			 main_img_src ||= @@agent.page.at('#prodImage')
	#      main_img_src ||= @@agent.page.at('#landingImage')
			 return nil unless main_img_src

			 return main_img_src['src']
		end

		def main_img_save(save_path, size1=nil, size2=nil)
			return nil unless @main_img_src
			dir = File::dirname(main_img_src) + "/"
			base = File::basename(main_img_src)
			base.gsub!(/\..+\./, "._SL#{size1}_AA#{size2}_.") if size2
			img_path = (base.gsub(/\..*/, "") + File.extname(base)) unless size2
			img_path = dir + base

			save_file = "#{save_path}n1#{File.extname(img_path)}"
			img_save(img_path, save_file)
		end

		def set_sub_img_src(ret=[])
			sub_img_src = nil

			div = @@agent.page.search('div#altImages')
			if sub_img_src = div.search('ul span img') then
				if sub_img_src && sub_img_src.length > 0 then
					sub_img_src.each {|img|
						if img['src'] then
						 img['src'] = img['src'].gsub(/_.+_\./, "_SL75_AA30_.")
						 ret.push img['src'] if img['src'] && File.extname(img['src']) =~ /jpg/i
						end
					}
					return ret
				end
			end

			unless sub_img_src && sub_img_src.length > 0 then
				if sub_img_src = @@agent.page.search('#thumb_strip img') then
					if sub_img_src && sub_img_src.length > 0 then
						sub_img_src.each {|img|
							ret.push img['src'] if img['src'] =~ /_(SL75)_(AA30)_/ && File.extname(img['src']) =~ /jpg/i
						}
						return ret
					end
				end
			end
			nil
		end

		def sub_img_save(save_path, size1 = nil, size2 = nil)
			return nil unless @sub_img_src
			@sub_img_src.each_with_index {|img_src, i|
				dir = File::dirname img_src
				base = File::basename img_src
				img_path = base.gsub(/\..+\./, "._SL#{size1}_AA#{size2}_.") if size2
				img_path = (base.gsub(/\..*/, "") + File.extname(base)) unless size2
				img_path = dir + '/' + img_path
	#       img_path = img['src'].gsub(/_.+_\./, "_SL#{size1}_AA#{size2}_.") if size2
	#       img_path = img['src'].gsub(/_.+_\./, "") unless size2
				if img_path then
					save_file = "#{save_path}n#{i+1}#{File.extname(img_path)}"
					img_save(img_path, save_file)
				end
			}
		end

end

class Amazon::ItemPage::Item < Amazon::ItemPage

	attr_reader :name, :page_uri, :short_uri, :price,
		:shipping, :price_and_shipping, :ranking, :stock,
		#
		:detail_all, :detail,
		:weight, :release_amazon, :release_brand, :brand, :model_num, 
		:isbn, :ean, :dimentions
	#
	TEXT_SPLIT_PTN = /#{"[:](.*)"}/

	######
	NO_INCLUDE_REGION_PTN1 = /Amazon.*(ランキング|ベストセラー)/
	NO_INCLUDE_PTN = /(おすすめ度)|(Amazon.*(ランキング|ベストセラー))/

	def initialize
		@isbn = [] 
		@weight = {}
		@release_amazon = {}
		@release_brand = {}
		@brand = {}
		@model_num = {}
#     @asin = {}
		@ean = {}
		@dimentions = {}
		@isbn = []

#     self.set if @@agent.page
		self
	end

	def set
		@name = set_name
		@short_uri = set_short_uri
		@page_uri = set_page_uri
		@price = set_price
		@shipping = set_shipping
		@price_and_shipping = @price > 0 ? @price + @shipping : 0
		@ranking = set_ranking
		@stock = set_stock
		@detail_all = Detail.get
		@detail = self.set_detail
		self
	end

	def set_stock(stock={amazon: 0, seller_new: 0, seller_used: 0})
		div = nil
		if div = @@agent.page.at("#availability") 
			stock[:amazon] = $1.to_i if div.at('b').text =~ /(\d.*?)[^\d]/  if div.at('b')
			unless $1
				if div.text =~ /(在庫)有り|あり/
					div.text =~ /(\d.*?)(.*在庫)/
					stock[:amazon] = $1 ? $1.to_i : 100
				end
				stock[:amazon] = 777 if div.text =~ /発売予定/
			end
		end

		stock[:amazon] = 777 if div.text =~ /発売予定/ if div = @@agent.page.at('.availOrange')
		if div = @@agent.page.at(".availGreen")
				if div.text =~ /(在庫)有り|あり/
					div.text =~ /(\d.*?)(.*在庫)/
					stock[:amazon] = $1 ? $1.to_i : 100
				end
#       stock[:amazon] = 100 if div.text =~ /(在庫)有り|あり/ 
		end

		if div = @@agent.page.at("#olpDivId")
			stock[:seller_new] = $1.to_i if div.text =~ /新品.*?(\d.*?)([^\d]|$)/
			stock[:seller_used] = $1.to_i if div.text =~ /中古.*?(\d.*?)([^\d]|$)/
		end
		if div = @@agent.page.at("#olp_feature_div")
			stock[:seller_new] = $1.to_i if div.text =~ /新品.*?(\d.*?)([^\d]|$)/
			stock[:seller_used] = $1.to_i if div.text =~ /中古.*?(\d.*?)([^\d]|$)/
		end
		stock
	end

	def set_shipping
		div ||= @@agent.page.at('#ourprice_shippingmessage')
		div ||= @@agent.page.at('#actualPriceExtraMessaging')
		return 0 if div.text =~ /無料/ if div
		if div = @@agent.page.at('.a-size-small.a-color-secondary.shipping3P') 
			return $1.to_f if div.text =~ /(\d.*?)[^\d]/
		end
		return 0
	end

	def set_page_uri
		@@agent.page.uri
	end

	def set_short_uri
		uri = @@agent.page.uri.to_s + "/"
		"#{Amazon.base_url(uri)}/dp/#{asin}"
	end
	def set_name
		div ||= @@agent.page.at('#productTitle')
		div ||= @@agent.page.at('#btAsinTitle')
		return div.text.gsub(/[\t\n\r]/, "").strip if div
	end
	
	def set_price
		price = @@agent.page.at('#priceblock_ourprice')
		price ||= @@agent.page.at('#priceblock_saleprice')
		price ||= @@agent.page.at('#actualPriceRow')
		price ||= @@agent.page.at('.priceLarge')
		return price.text.gsub(/[^\d.]/, "").to_f if price
		return 0
	end

	def set_ranking
		div = @@agent.page.at("#SalesRank")
		return $1.gsub(/[^\d]/, "").to_i if div.text.match(/(\d.*?)[^\d,]/) if div
		return 0
	end

	def set_detail(ret=[])
		@detail_all.each {|n|
			if n[:label] =~ /amazon.*開始日/i then
				@release_amazon = set_release(n)
			elsif n[:label] =~ /発売日/ then
				@release_brand = set_release(n)
				ret.push n
			elsif n[:label] =~ /発送重量/ then
				@weight = set_weight(n)
			elsif n[:label] =~ /商品パッケージ/ then
				@dimentions = n
			elsif n[:label] =~ /型番|製造元リファレンス/ then
				@model_num = n
			elsif n[:label] =~ /販売|出版社/ then
				@brand = n
				@brand[:value] = n[:value].split(/[;；（()]/)[0]
			elsif n[:label] =~ /asin/i then
#         @asin = n
			elsif n[:label] =~ /isbn/i then
				@isbn.push n
			elsif n[:label] =~ /ean/i then
				@ean = n
			elsif n[:label] =~ NO_INCLUDE_PTN
			else
				ret.push n
			end

			if @brand.empty? then
				if div = @@agent.page.at("#brand") then
					@brand[:label] = "メーカー"
					@brand[:value] = div.text.gsub(/\s　/, "")
					@brand[:label_value] = "#{@brand[:label]}:#{@brand[:value]}"
				end
			end
		}

		ret
	end

	def detail_en()
		self.translate_detail(@detail)
	end

	def translate_detail(nodes)
			nodes.each.map {|info|
				lb = Google::Translate.get(info[:label].gsub(/[\s　]/, "")) if info[:label]
				vl = Google::Translate.get(info[:value].gsub(/[\s　]/, "")) if info[:value]
				({label: lb, value: vl, label_value: "#{lb}:#{vl}" })
			}.compact
	end

	def set_weight(n = nil, ret={})
		 ret[:label_value] = n[:label_value]
		 weight = n[:value].gsub(/[^\d\.,]/, "").to_f
		 if n[:value].match(/kg/i) then
			 ret[:round] = (weight * 1000).to_i
			 ret[:value] = (weight * 1000).to_i
		 else
			 ret[:round] = ((weight / 100).to_i * 100) + 100
			 ret[:value] = weight.to_i
		 end

		return ret
	end
	private :set_weight

	def set_release(n = nil, ret={})
			ret[:label_value] = n[:label_value]
			ret[:label] = n[:label]
			begin
				d = n[:value].split(/\//).map {|v| v.to_i}
				if d.length < 3 then
					ret[:value] = Date::strptime(n[:value], "%Y/%m")
					ret[:text] = ret[:value].strftime("%Y/%m")
				end
				ret[:value] ||= Date.new(d[0], d[1], d[2])
				ret[:text] ||= ret[:value].strftime("%Y/%m/%d")
			rescue => ex
				puts ex.message
				ret = {}
			end

			return ret
		ret
	end
	private :set_release


end
class Amazon::ItemPage::Detail < Amazon::ItemPage::Item
	attr_reader :detail, :detail_all
	REGION_PTN = /リージョン/
	TEXT_SPLIT_PTN = /#{"[:](.*)"}/

	def all
		@detail_all
	end

	class << self
			def get(ret=[])
		#ページの商品価格や在庫のブロック
			@@agent.page.search('#feature-bullets li').map {|node|
				next nil unless node
				next nil unless node.text.match(/[:：]/)
				text = node.text.gsub("：", ":").gsub(/[\s　]/, "")
				text.gsub!(/[(（].*/, "") if text =~ REGION_PTN
				sp_text = text.split(TEXT_SPLIT_PTN)
				ret.push ({label: sp_text[0], value: sp_text[1], label_value: "#{text}"})
			}

			#商品の詳細部分を取得する<Div span>で構成されている
			#全てのーページにあるとは限らない
			#ページの真ん中あたりに表示されていることが多い

			@@agent.page.search('div .tsTable .tsRow').each {|node|
				row_texts = node.search('span').map {|span| span.text}
				ret.push ({label: row_texts[0], value: row_texts[1], label_value: "#{row_texts[0]}:#{row_texts[1]}"})
			}
		#商品の情報部分を取得する
		#全てのーページにあるとは限らない
		#ページの真ん中あたりに表示されていることが多い
			@@agent.page.search("#prodDetails tr").each {|node|
	#       break if node.at('script') 
				lb = node.at('.label')
				vl = node.at('.value')
				if lb && vl then
					ret.push ({label: lb.text, value: vl.text, label_value: "#{lb.text}:#{vl.text}"})
				end
			}
	#
			#登録情報を取得する
			#存在することが多い
			@@agent.page.search("//div[@id='detail_bullets_id' or @id='detail-bullets']//li").each {|node|
				next if node.at('script')
				next unless node.attributes.empty?
				text = node.text.gsub("：", ":").gsub(/[\s　]/, "")
				next if text.match(/おすすめ度/) if text
				text.gsub!(/[(（].*/, "") if text =~ REGION_PTN
				sp_text = text.split(TEXT_SPLIT_PTN)
				ret.push ({label: sp_text[0], value: sp_text[1], label_value: "#{text}"})
			}

			return ret.compact.uniq
		end
	end
end
class Amazon::SearchPage < Amazon
	
	attr_reader :items, :read_count, :result_count

	def initialize()
		@@agent = Mechanize.new.set
	  @@agent.redirection_limit=3
	end

	def get(word_or_uri, category = nil)
		if word_or_uri =~ /^http.*amazon/ then
			@@agent.get word_or_uri
		else
			@@agent.get(@@base_url)
			@@agent.page.form.field_with(name: "field-keywords").value = word_or_uri
			if category then
				@@agent.page.form.field_with(name: "url") {|list|
					list.option_with(text: category).select
				}
			end
			@@agent.page.form.click_button
		end


		@items = set_items
		@result_count = set_result_count
		@read_count = nil
		self
	end

	def set
		@items = set_items
	end

	def page
		@@agent.page
	end

	def title
		@@agent.page.title
	end

	def set_result_count
		div = @@agent.page.at('#result-count')
		div = @@agent.page.at('#s-result-count') unless div
		return 0 unless div
		text = div.text.strip.gsub(/\d-(.*?)[^\d]/, "")
	  $1.gsub(",", "").to_i if text.match(/(\d.*?)[^\d^,]/) 
	end

	def location
		@@agent.page.uri.to_s =~ /&page=(\d+)/
		return $1.to_i if $1
	end

	def read_count
		unless @read_count then
		 @read_count = (location-1) * 24 if location
		 @read_count ||= 0
		end
		return @read_count+=1
	end

	def next_page?
		 true if @@agent.page.link_with(id: "pagnNextLink")
	end

	def next_page(next_link=nil)
		 return nil unless next_link = @@agent.page.link_with(id: "pagnNextLink")
		 next_link.click
		 self.set
		 self
	end

	def set_items
		ret = []
		node = nil

		item_div =  @@agent.page.search("#rightResultsATF .prod.celwidget")
		item_div.each {|div|
			item = Item.new
			item.name = node.text.gsub(/[\r\n\r]/, "").strip if node = div.at('.newaps')
			item.page_uri = node['href'] if node = div.at('a')
			item.page_uri.to_s =~ /\/dp\/(.+?)\//
			item.asin = $1
			item.short_uri = "#{Amazon.base_url(item.page_uri.to_s)}/dp/#{item.asin}/"

			if node = div.at('.bld.lrg.red')
#         puts price = node.text.match(/(\d.*?)[^\d]/)[1]
#         puts node.text
				price =  node.text =~ /(\d.*?)[^\d\.,]/
				price ||= node.text =~ /(\d.*)/
				item.price[:amazon] = $1.gsub(/[^\d.]/, "").to_f if $1
			end
			if node = div.search('.med.grey') then
				node.each {|n|
				if n.text =~ /(\d.*?)[^\d,.]/ then
					price = $1
					item.price[:seller_new] = price.gsub(/[^\d.]/, "").to_f if n.text =~ /新品|new/i
					item.price[:seller_used] = price.gsub(/[^\d.]/, "").to_f if n.text =~ /中古|used/i
				end
			}
			end

			item.stock[:amazon] = 100 if div.at('.bld.grn.nowrp')
			if node = div.at('.red.sml') then
				item.stock[:amazon] = $1.to_i if node.text =~ /(\d.*?)[^\d]/
			end
			item.stock[:amazon] ||= 777 if item.price[:amazon] #&& div.at('.grey.sml') #unknown
			item.stock[:amazon] ||= 0

			if rows = div.search('li.med.grey.mkp2') then
				rows.each {|li|
					if li.text.strip =~ /新品|new/i then
						 item.stock[:seller_new] = $1.to_i if li.at('.grey').text =~ /(\d.*?)[^\d]/ if li.at('.grey')
					elsif li.text.strip =~ /中古|used/i 
						 item.stock[:seller_used] =  $1.to_i if li.at('.grey').text =~ /(\d.*?)[^\d]/ if li.at('.grey')
					end
				}
			end
#         item.stock[:seller_new] = $1.to_i if node.text =~ /(\d.*?\d?)/
			item.stock[:seller_new] ||= 0
			item.stock[:seller_used] ||= 0
#       item.img = div.search('img')
			ret.push item
		}

		ret
	end
end

class Amazon::SearchPage::Item

	attr_accessor :name, :name_en, :page_uri, :short_uri, :price, :search_page_uri,
		:asin, :stock, :model_num, :img

	def initialize(url=nil)
		@price = {}
		@stock = {}
	end

#   def page
#     item_page = Amazon::ItemPage.new
#     item_page.get(@page_uri)
#   end

	def all
		return { 
#         search_page_uri: @search_page_uri,
				page_uri: @page_uri,
				short_uri: @short_uri,
				asin: @asin,
				name: @name,
				name_en: @name_en,
				amazon_price: @price[:amazon],
				stock_amazon: @stock[:amazon],
				stock_seller_new: @stock[:seller_new],
				stock_seller_used: @stock[:seller_used],
				model_num: @model_num,
				img: @img
		}
	end

	class << self
		def all_key
			self.new.all.each_key.map
		end
	end

end


class Amazon::SellerCentral
	attr_reader :data

  def initialize
    @driver = Selenium::WebDriver.for :phantomjs
		@agent = Mechanize.new
    @base_url = "https://sellercentral.amazon.co.jp/"
		@base_uri = @base_url + "/gp/fba/revenue-calculator/index.html/"
    @accept_next_alert = true
    @driver.manage.timeouts.implicit_wait = 30
		@wait = Selenium::WebDriver::Wait.new(:timeout => 5)
  end
  
  def quit
    @driver.quit
  end
  
	def wait_time(t)
		@wait = Selenium::WebDriver::Wait.new(:timeout => t)
	end

  def get(asin)
		@data = Amazon::SellerCentral::Data.new
		@driver.get(@base_uri) unless @driver.current_url =~ /http.?/
			
#     @wait.until {@driver.execute_script("return document.readyState;") == "complete"}
		@wait.until {@driver.find_element(:tag_name, "h1")}
		@driver.find_element(:id, "search-string").clear
		@driver.find_element(:id, "search-string").send_keys asin
		@wait.until {@search_button = @driver.find_element(:id, 'search-products')}
		@search_button.click

		@wait.until {@next_link = @driver.find_element(:id, "search-again")}
		@wait.until {not @next_link.text.empty?}
#       @wait.until {@driver.find_element(:xpath, "//*[@id='selected-product']//*")}

		@agent.parse_html(@driver.page_source, @base_url)
		if div = @agent.page.at("#selected-product .main") then
			@data.name = @elem.text if @elem = div.at('strong')
			@data.dimention = $1 if div.text =~ /商品の寸法.*?(\d.*\d)/
			@data.asin = $1 if div.text =~ /asin:.*?(\w.*\w)/i
			if div.text =~ /重量.*?(\d.*?[^\.^\d])/
				wt = ($1.to_f*1000).to_i
				@data.weight[:round] = ((wt / 100) * 100) + 100
				@data.weight[:value] = wt
			end
		end

		div = @agent.page.at("#product-info-link")
		@data.amazon_link = div['href'] if div


    @next_link.click
		@data
  end
  
	def weight
		@data.weight
	end
	def dimention
		@data.dimention
	end
end

class Amazon::SellerCentral::Data
	attr_accessor :weight, :dimention, :name, :asin, :amazon_link
	def initialize
		@weight = {}
	end
end


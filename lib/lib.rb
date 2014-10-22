base = File.expand_path File.dirname(__FILE__)
require 'mechanize'
require 'selenium-webdriver'
require "socksify"
require "socksify/http"

class MechanizeEx
	attr_accessor :perser

	def agent; @@agent end
	def driver; @@driver end

	def initialize(param = {:perser => "mechanize"})
		@perser = param[:perser]
		if @perser == "selenium"
			pr = ProxySearch.speed()[1]
			pr = "#{pr[:host]}:#{pr[:port]}"
#       capabilities = Selenium::WebDriver::Remote::Capabilities.phantomjs(
#         'phantomjs.page.settings.userAgent' => 'Mozilla/5.0 (Windows NT 6.1; Trident/7.0; rv:11.0) like Gecko',
#       )
			 
			capabilities = {'proxy' => {:proxyType => 'manual', :httpProxy => pr, :httpsProxy => pr}}
			@@driver = Selenium::WebDriver.for :phantomjs, :args => "--proxy=#{pr}"
#       @@driver = Selenium::WebDriver.for :phantomjs, :desired_capabilities => capabilities
		end
		@@agent = Mechanize.new.set
	end

	def proxy(host, port)
		if perser == "selenium"
		end
	end

	def set
		self
	end

	def get(url)
		@@agent.get(url) if @perser == "mechanize"
		if @perser == "selenium"
			@@driver.get(url)
			@@agent.parse_html(@@driver.page_source, @@driver.current_url)
		end
		@@agent.page
	end
end

class Mechanize::HTTP::Agent
	def set_socks addr, port
		set_http unless @http
		class << @http
			attr_accessor :socks_addr, :socks_port
		 
			def http_class
				Net::HTTP.SOCKSProxy(socks_addr, socks_port)
			end
		end
		@http.socks_addr = addr
		@http.socks_port = port
	end
end

class Mechanize
	def parse_html(data, uri="http://www.example.com")
		uri = URI.parse(uri) unless uri.is_a?(URI)
		page = Mechanize::Page.new( uri, {'content-type' => 'text/html'}, data, "200", self)
		self.history.push(page)
		page
	end

	def set
		self.max_history = 1
		self.read_timeout = 5
		self.open_timeout = 5
		self.follow_meta_refresh = true
		self.redirection_limit=5
		self.user_agent_alias = 'Windows Mozilla'
		self.request_headers = {'accept-language' => 'en'}
		self
	end

end
$wait = Selenium::WebDriver::Wait.new(:timeout => 8)

class Selenium::WebDriver::Driver

	def set(param = {:wait => 5})
		self.manage.timeouts.implicit_wait = param[:wait]
		self
	end
	def search_wait
		$wait
	end
	def search_wait=(t)
		$wait = Selenium::WebDriver::Wait.new(:timeout => t)
	end
	def get_param(param)
		match = param =~ /(^#|^\/\/)/ ? $1 : nil
		return :tag_name => param unless match
		return :id => param[1..param.length] if match == "#"
		return :xpath => param if match == "//"
	end
	def search(param)
		$wait.until { self.find_elements(get_param(param)) }
	end
	def at(param)
		$wait.until { self.find_element(get_param(param)) }
	end
end

class Selenium::WebDriver::Element
	def select(id, obj)
		Selenium::WebDriver::Support::Select.new(self).select_by(id, obj)
	end
end



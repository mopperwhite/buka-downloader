#!/usr/bin/env ruby
#encoding=UTF-8
require 'net/http'
require 'nokogiri'
require 'json'
require 'yaml'
require 'open-uri'
require 'base64'
require 'optparse'
module Buka
        module Info
                HOST="www.bukamh.cn"
                HEADER={
                        "Accept"=>"text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
                        "Accept-Encoding"=>"deflate,sdch",
                        "Accept-Language"=>"zh-CN,zh;q=0.8",
                        "Connection"=>"keep-alive",
                        "User-Agent"=>"Mozilla/5.0 (X11; Linux i686) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/35.0.1916.153 Safari/537.36"
                        }
        end
        class Chapter
                attr_accessor :book,:chapter,:links
                def initialize book,chapter,links
                        @book=book
                        @chapter=chapter
                        @links=links
                end
                def get_img piclink
                        url_head=['pic','pic2']
                        for h in url_head
                                begin
                                        url = "http://#{h}.bukamh.cn/pic/echo.php?p=#{Base64.urlsafe_encode64(piclink)}"
                                        uri=open url,Info::HEADER
                                        data=uri.read
                                        break
                                        rescue
                                end
                        end
                        data
                end
                def download path
                        puts "Downloading Chapter: #{@chapter}"
                        @links.each{|piclink|
                                index=/\/([^\/]+?)$/.match(piclink)[1]
                                fpath=File.join(path,index)
                                puts "Downloading: #{index} @#{@chapter}-#{@book}\twaiting for #{st=rand 2..5}sec."
                                open(fpath,'wb'){|f| f.write(get_img piclink)}
                                sleep st
                        }
                end
        end
        class Book
                attr_accessor :book,:chapters
                def initialize book,chapters
                        @book=book
                        @chapters=chapters
                end
                def download path='.'
                        bp=File.join path,@book
                        unless File.directory? bp
                                Dir.mkdir bp
                        end
                        puts "Downloading Book: #{@book}"
                        @chapters.each{|c|
                                cp=File.join bp,c.chapter
                                unless File.directory? cp
                                        Dir.mkdir cp
                                end
                                c.download cp
                        }
                end
        end
        class Downloader
                def initialize path='.'
                        @opener=Net::HTTP.start(Info::HOST)
                        @path=path
                end
                def del_space str
                        /^ +(.*) +$/.match(str)[1]
                end
                def get_chapter_by_path path
                        res=@opener.get path,Info::HEADER 
                        doc= Nokogiri::HTML res.body
                        book=del_space doc.css("a#cartoon_url").text
                        chapter=doc.css("div.mod-crumbs-s1").at("b").text
                        js_data=doc.xpath("//head/script").text
                        picTree_data=/var picTree = (\[.*\]);/.match(js_data)[1]
                        picTree=JSON.load picTree_data.gsub("'",'"')  # Ruby 的JSON 也不认单引号 = =
                        puts "@Chapter: #{chapter}\twaiting for #{st=1} sec."
                        sleep st
                        Chapter.new book,chapter,picTree
                end
                def get_book_by_path path
                        res=@opener.get(path,Info::HEADER)
                        doc= Nokogiri::HTML res.body
                        hover=doc.css "span.hover"
                        #~ p path
                        book=doc.css("h1").at("a").text
                        puts "@Book: #{book}"
                        chapters=hover.css("a").map{|a| get_chapter_by_path(a["href"])}
                        book=del_space(book) #去除前后空格
                        Book.new book,chapters
                end
                def get_chapter bid,cid
                        return get_chapter_by_path "/manhua/#{bid}/#{cid}.html"
                end
                def get_book bid
                        return get_book_by_path "/manhua/#{bid}/"
                end
                def get_book_links_by key
                        params={"s"=>"2","keyboard"=>key.encode("utf-8"),"show"=>"title,writer,m_content"}
                        res=@opener.post "/e/search/index.php",URI.encode_www_form(params),Info::HEADER
                        #~ p res.body
                        #~ p res.header.to_hash
                        result_response=@opener.get "http://www.bukamh.cn/e/search/#{res.header["location"]}",Info::HEADER
                        #Net::HTTP似乎应付不了重定向
                        #从header里抽出重定向后的地址，再GET
                        #BUG已修复
                        #~ p result_response.body
                        doc=Nokogiri::HTML result_response.body
                        return doc.css("div.pic").map{|d| d.at("a")["href"]}
                end
                def search key
                        puts get_book_links_by(key)
                        return get_book_links_by(key).map{|l|
                                get_book_by_path l
                        }
                end
        end
end

def get_options
        options={}
        OptionParser.new do |opts|
                opts.banner="#{__FILE__} [arguments] [book id]"
                opts.on_tail("-b BOOK_ID","--book BOOK_ID","Get book by id."){ |b| options[:book]=b }
                opts.on_tail("-s KEY","--search KEY","Search by the keyword and get all."){|key| options[:search]=key}
                opts.on_tail("-p PATH","--path PATH","Set download path."){|path| options[:path]=path}
                opts.on_tail("-y","--yaml","Store information as yaml."){|y| options[:yaml]=y}
                opts.on_tail("-d","--download","Download the gain books."){|d| options[:download]=d}
        end.parse!
        return options
end

def main
        downloader=Buka::Downloader.new
        options=get_options
        path='.'
        for opt in [:book,:search,:path,:yaml,:download]
                if options.has_key? opt
                        val=options[opt]
                        case opt
                        when :book
                                book_list=[downloader.get_book(val)]
                        when :search
                                book_list=downloader.search val
                        when :path
                                unless File.directory? val
                                        Dir.mkdir val
                                end
                                path=val
                        when :yaml
                                book_list.each {|book|
                                        open(File.join(path,book.book+".yaml"),'w').write book.to_yaml
                                }
                        when :download
                                book_list.each{|book| book.download path}
                        end
                end
        end
        
end

if __FILE__==$0
        main
end

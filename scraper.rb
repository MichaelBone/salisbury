require 'scraperwiki'
require 'mechanize'

agent = Mechanize.new

def extract_from_p(contents, name)
  contents.at('p:contains("' + name + '")').inner_text.split(name).last.strip
end

def scrape_page(page)
  
  # needs error checking particularly for date closing.
  # what if parse fails.

  contents = page.search('div.span6')
  record = {
    "info_url" => page.uri.to_s,
    "council_reference" => contents.search('h1').inner_text.strip,
    "comment_url" => page.uri.to_s,
    "applicatant" => extract_from_p(contents,"Applicant:"),
    "description" => contents.at('p:contains("Location:")').next_element.inner_text.strip,
    "address" => extract_from_p(contents,"Location:"),
    "date_scraped" => Date.today.to_s,
    "date_closing" => Date.strptime(extract_from_p(contents,"Advertising closes "),"%d %b %Y"),
  }

  if (ScraperWiki.select("* from data where `council_reference`='#{record['council_reference']}'").empty? rescue true)
    ScraperWiki.save_sqlite(['council_reference'], record)
  else
    puts "Skipping already saved record " + record['council_reference']
  end
end

base_url = "https://eservices.salisbury.sa.gov.au/ePathway/Production/Web"

puts "Retrieving the default page."
default_url = "#{base_url}/default.aspx"
default_page = agent.get(default_url)
default_page = agent.get(default_url + '?' + default_page.body.scan(/js=-?\d+/)[0])  # enable JavaScript

puts "Retrieving the enquiry lists page."
link = default_page.link_with(:href => 'GeneralEnquiry/EnquiryLists.aspx')
enquiry_lists_page = link.click

puts enquiry_lists_page.body

#url = "http://www.salisbury.sa.gov.au/Build/Planning_Building_and_Forms/Advertised_Development_Applications"
#page = agent.get(url)

#get links to new developments

apps_links = []

links = page.search('a')
links.each do |link|
  break
  href = link['href']

  if (href && href.start_with?("http://www.salisbury.sa.gov.au/Build/Planning_Building_and_Forms/Advertised_Development_Applications/") )
    apps_links << href
  end
end

apps_links.each_with_index do |app_url,index|
  puts "Scraping application #{index} of #{apps_links.length} ..."
  app = agent.get(app_url)
  scrape_page(app)
end

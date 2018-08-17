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
comment_url = "mailto:city@salisbury.sa.gov.au"

puts "Retrieving the default page."
default_url = "#{base_url}/default.aspx"
default_page = agent.get(default_url)
default_page = agent.get(default_url + '?' + default_page.body.scan(/js=-?\d+/)[0])  # enable JavaScript

puts "Retrieving the enquiry lists page."
link = default_page.link_with(:href => 'GeneralEnquiry/EnquiryLists.aspx')
enquiry_lists_page = link.click

# The Date tab defaults to a search range of the last 30 days.

puts "Clicking the Date tab."
enquiry_lists_form = enquiry_lists_page.forms.first
enquiry_lists_form['__EVENTTARGET'] = 'ctl00$MainBodyContent$mGeneralEnquirySearchControl$mTabControl$tabControlMenu'
enquiry_lists_form['__EVENTARGUMENT'] = '1'
enquiry_search_page = agent.submit(enquiry_lists_form)

puts "Clicking the Search button."
enquiry_search_form = enquiry_search_page.forms.first
button = enquiry_search_form.button_with(:value => "Search")
results_page = agent.submit(enquiry_search_form, button)

count = 0
development_applications = []
while results_page
  count += 1
  puts "Parsing the results on page #{count}."

  table = summary_page.root.at_css('.ContentPanel')
  headers = table.css('th').collect { |th| th.inner_text.strip }
  development_applications += table.css('.ContentPanel, .AlternateContentPanel').collect do |tr| 
    tr.css('td').collect { |td| td.inner_text.strip }
  end
  
  if count > 50  # safety precaution
    puts "Stopping paging after #{count} pages."
    break
  end

  next_page_image = results_page.root.at_xpath("//td/input[contains(@src, 'nextPage')]")
  results_page = nil
  if next_page_image
    next_page_path = next_page_img['onclick'].split(',').find { |e| e =~ /.*PageNumber=\d+.*/ }.gsub('"', '').strip
    puts "Retrieving the next page: #{next_page_path}"
    results_page = agent.get "#{base_url}/#{next_page_path}"
  endif
end

puts "Complete."
  
apps_links = []

links = enquiry_summary_view_page.search('a')
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

require 'scraperwiki'
require 'mechanize'

base_url = "https://eservices.salisbury.sa.gov.au/ePathway/Production/Web"
comment_url = "mailto:city@salisbury.sa.gov.au"

agent = Mechanize.new

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
applications = []
while results_page
  count += 1
  puts "Parsing the results on page #{count}."

  table = results_page.root.at_css('.ContentPanel')
  headers = table.css('th').collect { |th| th.inner_text.strip }
  applications += table.css('.ContentPanel, .AlternateContentPanel').collect do |tr| 
    tr.css('td').collect { |td| td.inner_text.strip }
  end
  
  if count > 50  # safety precaution
    puts "Stopping paging after #{count} pages."
    break
  end

  next_page_image = results_page.root.at_xpath("//td/input[contains(@src, 'nextPage')]")
  results_page = nil
  if next_page_image
    next_page_path = next_page_image['onclick'].split(',').find { |e| e =~ /.*PageNumber=\d+.*/ }.gsub('"', '').strip
    puts "Retrieving the next page: #{next_page_path}"
    results_page = agent.get "#{base_url}/GeneralEnquiry/#{next_page_path}"
  end
end

# Construct development application records that can be inserted into the database.

application_records = applications.collect do |application|
  application_record = {}
  application_record['council_reference'] = application[headers.index('Application Number')]
  application_record['info_url'] = "#{base_url}/default.aspx"
  application_record['description'] = application[headers.index('Application Description')]
  application_record['date_received'] = Date.strptime(application[headers.index('Lodgement Date')], '%d/%m/%Y').to_s
  application_record['address'] = application[headers.index('Site Address')]
  application_record['date_scraped'] = Date.today.to_s
  application_record['comment_url'] = comment_url
  if application_record['description'].strip == ''
    application_record['description'] = 'No description provided'
  end
  application_record
end

# Insert the records into the database.

puts "Updating the database."
application_records.each do |application_record|
  if application_record['council_reference'] != '' && application_record['address'] != ''  # avoid invalid records
    if (ScraperWiki.select("* from data where `council_reference`='#{application_record['council_reference']}'").empty? rescue true)
      ScraperWiki.save_sqlite(['council_reference'], application_record)
      puts "Inserted: application \"" + application_record['council_reference'] + "\" with address \"" + application_record['address'] + "\" and description \"" + application_record['description'] + "\" into the database."
    else
      puts "Skipped: application \"" + application_record['council_reference'] + "\" with address \"" + application_record['address'] + "\" and description \"" + application_record['description'] + "\" because it was already present in the database."
    end
  end
end

puts "Complete."

#!/usr/bin/env ruby
# frozen_string_literal: true

# NPSchema: Not Perfect Non Profit fieldnames and schema
#   Simplistic shared field, url, pattern defnitions.
# Other parsing ideas
#   link rel="amphtml" provides AMP pages for Google?
module NPSchema
  NORMALIZE_MAP = { # HACK: normalize chars that drive me crazy
    ' ' => ' ',
    '’' => "'",
    '‘' => "'",
    '–' => '-'
  }.freeze
  NORMALIZE_PAT = /[ ’‘–]/
  SOCIAL_MAP = { # TODO: update to capture just id's per service
    'twitter' => /twitter.com/i,
    'facebook' => /facebook.com/i,
    'instagram' => /instagram.com/i,
    'linkedin' => /linkedin.com/i,
    'tiktok' => /tiktok.com/i,
    'threads' => /threads.net/i,
    'bluesky' => /bsky.app/i,
    'youtube' => /youtube.com/i,
    'whatsapp' => /whatsapp.com/i,
    'snapchat' => /snapchat.com/i,
    'pinterest' => /pinterest.com/i,
    'reddit' => /reddit.com/i
  }.freeze
  # List some very simple CSS paths mapping to fields
  CSS_MAP = {
    'slogan' => '.site-description',
    'copyright' => '.copyright',
    'imprint' => '.imprint'
  }.freeze
  TEXT_MATCHES = 'textmatch'
  EIN_SCAN = 'einscan'
  # Mapping of rough text nodes that signify non-profit status
  TEXTRX_MAP = {
    'nonprofit' => /non[-\s]?profit/i,
    '501c3' => /501[(\s]*c[)\s]*[(\s]*3[)\s]*/i,
    '501c6' => /501[(\s]*c[)\s]*[(\s]*6[)\s]*/i,
    # See https://www.irs.gov/businesses/small-businesses-self-employed/how-eins-are-assigned-and-valid-ein-prefixes
    # FIXME: refactor to pass rubocop checks
    # rubocop:disable Layout/LineLength
    EIN_SCAN => /(tax\s+id:?|ein:?)\D+(01|02|03|04|05|06|10|11|12|13|14|15|16|20|21|22|23|24|25|26|27|30|32|33|34|35|36|37|38|39|40|41|42|43|44|45|46|47|48|50|51|52|53|54|55|56|57|58|59|60|61|62|63|64|65|66|67|68|71|72|73|74|75|76|77|80|81|82|83|84|85|86|87|88|90|91|92|93|94|95|98|99|)-?\d{7}/i
    # rubocop:enable Layout/LineLength
  }.freeze
  METAS = 'metas'
  LINKS = 'links'
  NAVLINKS = 'linksnav'
  FOOTERLINKS = 'linksfooter'
  ALLLINKS = 'alllinks'
  # Mapping of scrape hash keys to regex patterns to look for
  LINKRX_MAP = {
    'aboutlinks' => /\Aabout-?u?/i,
    'boardlinks' => /\Aboard/i, # others: Advisory, Community, Editorial, etc
    'bylawlinks' => /bylaws/i,
    'budgetlinks' => /(budget|finance)/i,
    'teamlinks' => /\A(meet|our|the)[\w\s]+(team|staff)/i, # others: Team Bios
    'missionlinks' => /[\w\s]*mission\z/i, # others: Mission and Values
    'policylinks' => /[\w\s]*polic\w*\z/i, # others: Our values
    'brandlinks' => /\A(brand|trademark)[\w\s]*\z/i,
    'projectlinks' => /project/i,
    'eventlinks' => /event/i,
    'securitylinks' => /security/i,
    'coclinks' => /\Acode of[\w\s]*\z/i,
    'contactlinks' => /\Acontact[\w\s]*\z/i,
    'contributelinks' => /^(contribut|support|give)/i,
    'sponsorlinks' => /sponsor/i,
    'donatelinks' => /\Adonat/i
  }.freeze
end

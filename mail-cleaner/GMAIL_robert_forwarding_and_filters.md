# robert.olen@gmail.com — stop forwarding + auto-delete junk

Decisions (2026-06-11): stop forwarding Gmail→iCloud, read Gmail directly in
Apple Mail, and auto-delete the junk senders in Gmail going forward.

## 1. Turn OFF forwarding (this is what floods iCloud)

Gmail (signed in as robert.olen@gmail.com) → ⚙️ → **See all settings** →
**Forwarding and POP/IMAP**:
- Under **Forwarding**, if "Forward a copy of incoming mail to …" is selected,
  switch to **"Disable forwarding"** → **Save Changes** (bottom).
- Then check **Filters and Blocked Addresses** for any filter whose action is
  **"Forward to …"** — if forwarding was set up as a filter, delete/edit it
  (a global "Disable forwarding" does NOT stop a filter-based forward).

A Gmail filter that *deletes* mail does NOT stop global forwarding — global
forward sends everything regardless of filters. Disabling forwarding is the
only way to stop it.

## 2. Add robert.olen@gmail.com to Apple Mail (so you still read it)

Apple Mail → **Settings (⌘,)** → **Accounts** → **+** → **Google** →
sign in (browser OAuth — uses your Google login, not the app password) →
enable **Mail**. The Gmail account then appears in Apple Mail's sidebar with
its own Inbox/All Mail; iCloud's inbox stays clean.

## 3. Auto-delete junk filters (4 filters)

For EACH query below: paste it into Gmail's **search box** → click the
**"Show search options"** (sliders) icon → **Create filter** → check
**"Delete it"** → **Create filter**. (Don't tick "apply to existing" — already
trashed.) Four filters because Gmail caps filter query length.

### Filter 1
```
from:(notifications@nest.com OR googlealerts-noreply@google.com OR mailer-daemon@googlemail.com OR friendupdates@facebookmail.com OR notification@facebookmail.com OR close_friend_updates@facebookmail.com OR notification+oiiogiee@facebookmail.com OR info@twitter.com OR notify@twitter.com OR noreply@redditmail.com OR noreply@youtube.com OR notifications-noreply@linkedin.com OR invitations@linkedin.com OR newsdigest@insideapple.apple.com OR uspsinformeddelivery@email.informeddelivery.usps.com OR mcinfo@ups.com OR no-reply@familybase.vzw.com OR verizon-services@verizon.com OR email@email.buffnews.com OR digital@buffnews.com)
```

### Filter 2
```
from:(nm_buffalonews@newsmemory.com OR feedback@mail.mlblists.com OR store-news@amazon.com OR noreply@ebanned.net OR bestbuyinfo@emailinfo.bestbuy.com OR bestbuy@email.bestbuy.com OR bingo@patreon.com OR reply@email.thecpapshop.com OR cpap@hello.cpap.com OR hello@info.reverb.com OR email@e.fender.com OR walgreens@e.walgreens.com OR walgreens@eml.walgreens.com OR newsletter@email.buydig.com OR monoprice@news.monoprice.com OR no-reply@emails.monoprice.com OR no-reply@email.monoprice.com OR ebay@reply.ebay.com OR newsletters@audible.com OR microcenter@microcenterinsider.com)
```

### Filter 3
```
from:(info@bc.adorama.com OR yourfriends@e.sweetwater.com OR yourfriends@sweetwater.com OR specials@reader.macsales.com OR specials@macsales.com OR davidstea@email.davidstea.com OR news@stewmac.com OR info@emailsrv.swell.com OR emails@e.etsy.com OR sigsauer@sigsauer.com OR newsletter@indiegogo.com OR questions@bladehq.com OR donotreply@mcd.nikon.com OR noreply@e.buffalobills.com OR info@hsastore.com OR microsoftstore@microsoftstoreemail.com OR barnesandnoble@m.bn.com OR classmatesemail@email.classmates.com OR starbucks@e.starbucks.com OR info@mailer.netflix.com)
```

### Filter 4
```
from:(nintendo-noreply@nintendo.net OR bathandbodyworks@e2.bathandbodyworks.com OR homedepotcustomercare@email.homedepot.com OR costco@digital.costco.com OR support-newsletter@flightaware.com OR info@connect.isc2.org OR connect@isc2.org OR communications@faithlifemail.com OR communications@mail.logos.com OR communications@faithlife.net OR promotions@logosmail.com)
```

Note: financial senders (M&T, Wells Fargo, Capital One, BofA, PayPal) and
Amazon order/shipment receipts are deliberately NOT in these filters — they're
kept.

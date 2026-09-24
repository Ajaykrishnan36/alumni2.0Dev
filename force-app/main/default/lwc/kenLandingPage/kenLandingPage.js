import { LightningElement, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import KenLoginLogo from '@salesforce/resourceUrl/LoginKen';
import Casual1 from '@salesforce/resourceUrl/casual1';
import Casual2 from '@salesforce/resourceUrl/casual2';
import Casual3 from '@salesforce/resourceUrl/casual3';
import Event1 from '@salesforce/resourceUrl/Event1';
import Event2 from '@salesforce/resourceUrl/Event2';
import Event3 from '@salesforce/resourceUrl/Event3';
import Event4 from '@salesforce/resourceUrl/Event4';
import AlumniCommunityProfile1 from '@salesforce/resourceUrl/AlumniCommunityProfile1';
import AlumniCommunityProfile2 from '@salesforce/resourceUrl/AlumniCommunityProfile2';
import AlumniCommunityProfile3 from '@salesforce/resourceUrl/AlumniCommunityProfile3';
import AlumniCommunityCoverImg1 from '@salesforce/resourceUrl/AlumniCommunityCoverImg1';
import AlumniCommunityCoverImg2 from '@salesforce/resourceUrl/AlumniCommunityCoverImg2';
import AlumniCommunityCoverImg3 from '@salesforce/resourceUrl/AlumniCommunityCoverImg3';
import ClientLogoPost from '@salesforce/resourceUrl/clientLogoPost';
import InstaLogo from '@salesforce/resourceUrl/instaLogo';
import FacebookLogo from '@salesforce/resourceUrl/facebookLogo';
import LinkedinLogo from '@salesforce/resourceUrl/linkedinLogo';
import TwitterLogo from '@salesforce/resourceUrl/twitterLogo';
import StudentsSupported from '@salesforce/resourceUrl/StudentsSupported';
import YearsofGiving from '@salesforce/resourceUrl/YearsofGiving';
import CampaignsCompleted from '@salesforce/resourceUrl/CampaignsCompleted';
import CausesFunded from '@salesforce/resourceUrl/CausesFunded';
import FundraiserCoverImg from '@salesforce/resourceUrl/FundraiserCoverImg';
import NewsletterCoverImage1 from '@salesforce/resourceUrl/NewsletterCoverImage1';
import NewsletterCoverImage2 from '@salesforce/resourceUrl/NewsletterCoverImage2';
import NewsletterCoverImage3 from '@salesforce/resourceUrl/NewsletterCoverImage3';
import JointheAlumniPortalCoverImage from '@salesforce/resourceUrl/JointheAlumniPortalCoverImage';
import PoweredbyKen42WhiteColor from '@salesforce/resourceUrl/PoweredbyKen42WhiteColor';
import FIRA_SANS from '@salesforce/resourceUrl/firasansfont';
import Marcellus_Regular_Font from '@salesforce/resourceUrl/marcellusfont';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
import getEngagementOptions from '@salesforce/apex/KenEngagementPreferenceController.getOptions';
import getLandingPageEvents from '@salesforce/apex/KenLandingPageController.getLandingPageEvents';
import getLandingPageNewsletters from '@salesforce/apex/KenLandingPageController.getLandingPageNewsletters';
import getLandingPageStories from '@salesforce/apex/KenLandingPageController.getLandingPageStories';
import getLandingSocialPosts from '@salesforce/apex/KenLandingPageController.getLandingSocialPosts';
import getSocialProfileLinks from '@salesforce/apex/KenLandingPageController.getSocialProfileLinks';
import getContactEmailAddress from '@salesforce/apex/KenLandingPageController.getContactEmailAddress';
import getOrgContactDetails from '@salesforce/apex/KenLandingPageController.getOrgContactDetails';
// The three side cards keep the existing per-card styling, in the same order as
// the static markup, so a curated section looks identical to the current design.
const SIDE_CARD_VARIANTS = [
    { card: 'side-event-card toss-banner', content: 'toss-content' },
    { card: 'side-event-card silver-banner', content: 'silver-banner-content' },
    { card: 'side-event-card celebration-illustration', content: 'celebration-illustration-content' }
];

// The community band is a three-column grid, so it always renders three cards.
// Apex caps its side at the same number.
const SOCIAL_CARD_COUNT = 3;

// Shown on the filler cards only. Real cards take their handle from the
// platform's own config record, never from here.
const FALLBACK_HANDLE = '@institute';

export default class KenLandingPage extends NavigationMixin(LightningElement) {
    @track landingLogoUrl = '';
    @track socialLinks = {};
    @track contactEmail = '';
    @track contactPhone = '';
    @track contactLocation = '';
    // Overwritten by Ken_Alm_Org_Parameters__c.Institution_Name__c once
    // getPortalConfigs resolves; this default only covers the brief window
    // before that call returns.
    @track institutionName = 'Institute';
    @track preferences = [];
    // Events an admin ticked "Show On Landing Page" on. Empty means nobody has
    // curated the section yet, so the static cards below stay in place.
    @track landingEvents = [];
    // Newsletters uploaded to the Gallery's "Newsletter" album, newest first.
    // Empty means nothing has been uploaded yet, so the static cards stay.
    @track landingNewsletters = [];
    // Alumni stories an admin flagged on the Constituent Role. Empty means
    // nothing is published yet, so the static cards stay.
    @track landingStories = [];
    // Synced social posts, newest first across every platform, topped up to three
    // with the band's original static cards. Never shorter than three, so the row
    // cannot look half-built while the feed is still filling up.
    @track landingSocialPosts = [];
    event1 = Event1;
    event2 = Event2;
    event3 = Event3;
    event4 = Event4;
    communityCoverImg1 = AlumniCommunityCoverImg1;
    communityCoverImg2 = AlumniCommunityCoverImg2;
    communityCoverImg3 = AlumniCommunityCoverImg3;
    clientLogoPost = ClientLogoPost;
    instaLogo = InstaLogo;
    facebookLogo = FacebookLogo;
    linkedinLogo = LinkedinLogo;
    twitterLogo = TwitterLogo;
    fundraiserImage = FundraiserCoverImg;
    studentsSupported = StudentsSupported;
    yearsofGiving = YearsofGiving;
    campaignsCompleted = CampaignsCompleted;
    causesFunded = CausesFunded;
    newsletterCoverImage1 = NewsletterCoverImage1;
    newsletterCoverImage2 = NewsletterCoverImage2;
    newsletterCoverImage3 = NewsletterCoverImage3;
    joinPortalCoverImage = JointheAlumniPortalCoverImage;
    poweredByLogo = PoweredbyKen42WhiteColor;
    alumniProfile1 = AlumniCommunityProfile1;
    alumniProfile2 = AlumniCommunityProfile2;
    alumniProfile3 = AlumniCommunityProfile3;
    
    @track currentSlide = 0;
    @track isMenuOpen = false;
    @track showMapModal = false;
    mapModalHeight = 520;
    @track headerOffsetPx = 90;

    get mapModalOverlayStyle() {
        return `top: ${this.headerOffsetPx}px;`;
    }

    // Header logo. Blank until an admin uploads a real one via
    // Ken_Alm_Org_Parameters__c.Landing_Page_Logo_URL__c, so the placeholder
    // graphic keeps rendering rather than a broken <img>.
    get landingLogo() {
        return this.landingLogoUrl || KenLoginLogo;
    }

    // No fallback: a platform with nothing configured in Ken_Alm_Integration_Settings__mdt
    // returns undefined here, which LWC renders as no href attribute at all -
    // an inert icon, exactly like a social post card with no Post_URL__c. This
    // never points a visitor at a generic platform homepage that isn't
    // actually the institution's own page.
    get facebookProfileUrl() {
        return this.socialLinks.Facebook;
    }

    get instagramProfileUrl() {
        return this.socialLinks.Instagram;
    }

    get twitterProfileUrl() {
        return this.socialLinks.X;
    }

    get linkedinProfileUrl() {
        return this.socialLinks.LinkedIn;
    }

    get hasContactEmail() {
        return !!this.contactEmail;
    }

    get contactEmailHref() {
        return this.contactEmail ? `mailto:${this.contactEmail}` : '';
    }

    get hasContactPhone() {
        return !!this.contactPhone;
    }

    get contactPhoneHref() {
        return this.contactPhone ? `tel:${this.contactPhone}` : '';
    }

    get hasContactLocation() {
        return !!this.contactLocation;
    }

    carouselImages = [Casual1, Casual2, Casual3];

    connectedCallback() {  // use effect -> in react
        getPrimaryColor().then(color => {
            this.institutionName = color?.institutionName || this.institutionName;
            this.landingLogoUrl = color?.landingPageLogoUrl || '';
            document.documentElement.style.setProperty('--primary-color', color?.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', color?.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', color?.tertiaryColor);
        }).catch(() => {
            console.log('Error getting primary color');
        });
        // Load custom fonts
        this.loadCustomFonts();
        this.loadCustomFonts1();
        this.loadPreferences();
        this.loadLandingEvents();
        this.loadLandingNewsletters();
        this.loadLandingStories();
        this.loadLandingSocialPosts();
        this.loadSocialProfileLinks();
        this.loadContactEmail();
        this.loadOrgContactDetails();
        // Auto-rotate carousel every 5 seconds
        this.carouselInterval = setInterval(() => {
            this.nextSlide();
        }, 5000);
    }

    // Footer social icon hrefs. Empty result (or a rejected call) just leaves
    // socialLinks empty, and every getter above falls back to the generic
    // platform homepage rather than a broken or wrong link.
    loadSocialProfileLinks() {
        getSocialProfileLinks()
            .then(links => {
                this.socialLinks = links || {};
            })
            .catch(() => {
                this.socialLinks = {};
            });
    }

    // Footer contact email. Left blank on failure/no match, which hides the
    // row (hasContactEmail) rather than show a wrong or empty address.
    loadContactEmail() {
        getContactEmailAddress()
            .then(email => {
                this.contactEmail = email || '';
            })
            .catch(() => {
                this.contactEmail = '';
            });
    }

    // Footer phone/location, read from the standard Organization record
    // (Setup > Company Information). Left blank on failure/no data, which
    // hides each row (hasContactPhone/hasContactLocation) rather than show a
    // wrong or empty value.
    loadOrgContactDetails() {
        getOrgContactDetails()
            .then(details => {
                this.contactPhone = details?.phone || '';
                this.contactLocation = details?.location || '';
            })
            .catch(() => {
                this.contactPhone = '';
                this.contactLocation = '';
            });
    }

    get hasPreferences() {
        return this.preferences && this.preferences.length > 0;
    }

    // True once an admin has flagged at least one event; until then the section
    // keeps its static cards rather than rendering an empty band on a public page.
    get hasLandingEvents() {
        return this.landingEvents && this.landingEvents.length > 0;
    }

    // First flagged event fills the large hero card.
    get landingMainEvent() {
        return this.hasLandingEvents ? this.landingEvents[0] : null;
    }

    // Remaining flagged events fill the three smaller cards beside it.
    get landingSideEvents() {
        return this.hasLandingEvents ? this.landingEvents.slice(1) : [];
    }

    // Loads the events an admin ticked "Show On Landing Page" on.
    loadLandingEvents() {
        getLandingPageEvents()
            .then(records => {
                const list = Array.isArray(records) ? records : [];
                const fallbacks = [this.event1, this.event2, this.event3, this.event4];
                this.landingEvents = list.map((rec, index) => {
                    const location = (rec.location || '').trim();
                    // Events are day-granular — Start_Date__c / End_Date__c with no
                    // time of their own — so the server-built label is correct for
                    // every visitor. A Date has no timezone, which is why this is
                    // safe even under the site guest user, whose timezone nobody
                    // has ever set.
                    const dateLabel = (rec.dateLabel || '').trim();
                    // Index 0 is the hero card; 1-3 are the side cards, which take
                    // the same variant styling as their static counterparts.
                    const variant = SIDE_CARD_VARIANTS[index - 1] || SIDE_CARD_VARIANTS[0];
                    return {
                        id: rec.id,
                        title: rec.title,
                        badge: rec.badge,
                        dateLabel,
                        hasDateLabel: !!dateLabel,
                        location,
                        hasLocation: !!location,
                        cardClass: variant.card,
                        contentClass: variant.content,
                        backgroundStyle: this.buildEventBackground(rec.imageUrl, fallbacks[index])
                    };
                });
            })
            .catch(() => {
                // Fall back to the static cards rather than blanking the section.
                this.landingEvents = [];
            });
    }

    // True once at least one alumni story is published; until then the section
    // keeps its static cards rather than rendering an empty row.
    get hasLandingStories() {
        return this.landingStories && this.landingStories.length > 0;
    }

    // Loads the alumni stories an admin flagged on the Constituent Role.
    // A missing photo does NOT drop the card - unlike a newsletter, the quote is
    // the content and the portrait is dressing, so the card keeps its place and
    // shows the alumnus's initials instead.
    loadLandingStories() {
        getLandingPageStories()
            .then(records => {
                const list = Array.isArray(records) ? records : [];
                this.landingStories = list
                    .map(rec => {
                        const company = (rec.company || '').trim();
                        const role = (rec.role || '').trim();
                        const batchLabel = (rec.batchLabel || '').trim();
                        const name = (rec.name || '').trim();
                        const imageUrl = this.resolveStoryImage(rec.imageUrl);
                        return {
                            id: rec.id,
                            name,
                            company,
                            hasCompany: !!company,
                            role,
                            hasRole: !!role,
                            batchLabel,
                            hasBatchLabel: !!batchLabel,
                            quote: (rec.quote || '').trim(),
                            imageUrl,
                            hasImage: !!imageUrl,
                            initials: this.buildInitials(name)
                        };
                    })
                    // A story with no quote is just a portrait over empty space.
                    .filter(rec => !!rec.quote && !!rec.name);
            })
            .catch(() => {
                // Fall back to the static cards rather than blanking the section.
                this.landingStories = [];
            });
    }

    // Alumni photos are stored as free text, and a guest cannot load a Salesforce
    // login-protected one, so anything that is not an absolute http(s) link is
    // treated as no photo at all.
    //
    // A real alumnus is never given one of the static portraits. Those are stock
    // faces of other people, and the slot they were picked by was the row's
    // position in the query - so a named alumnus wore a stranger's face, and a
    // different stranger's once an edit reordered the rows.
    resolveStoryImage(imageUrl) {
        const raw = (imageUrl || '').trim();
        return /^https?:\/\//i.test(raw) ? raw : null;
    }

    // First and last initial, which is what stands in when there is no photo.
    // The card is filtered on a non-empty name, so this always has something to
    // work with.
    buildInitials(name) {
        const words = (name || '').trim().split(/\s+/).filter(Boolean);
        if (!words.length) {
            return '';
        }
        const first = words[0].charAt(0);
        const last = words.length > 1 ? words[words.length - 1].charAt(0) : '';
        return (first + last).toUpperCase();
    }

    // True once at least one synced post is renderable; until then the community
    // band keeps its static cards rather than rendering an empty row.
    get hasLandingSocialPosts() {
        return this.landingSocialPosts && this.landingSocialPosts.length > 0;
    }

    // Platform name -> the icon shown in the card's top-right corner. Returns ''
    // for anything unrecognised so the template hides the icon instead of
    // handing <img> an undefined src, and a post from a newly added platform
    // still renders its photo and caption.
    resolveSocialIcon(platform) {
        switch (platform) {
            case 'Instagram':
                return this.instaLogo;
            case 'Facebook':
                return this.facebookLogo;
            case 'LinkedIn':
                return this.linkedinLogo;
            case 'X':
                return this.twitterLogo;
            default:
                return '';
        }
    }

    // A synced post may carry no image - the platform returned none, or the
    // upload into Salesforce failed - so fall back to this slot's existing
    // static cover rather than handing <img> an empty src. Mirrors
    // resolveStoryImage; a guest cannot load a login-protected Salesforce link,
    // so only an absolute http(s) URL, a site-relative path, or a data image is
    // accepted.
    resolveSocialImage(imageUrl, fallbackImage) {
        const raw = (imageUrl || '').trim();
        const isUsable = /^(https?:\/\/|\/|data:image\/)/i.test(raw);
        return isUsable ? raw : (fallbackImage || this.communityCoverImg1);
    }

    // The card links out to the post on the platform. Only an absolute http(s)
    // URL is allowed through, so a blank or malformed value cannot become a
    // relative link that navigates inside the portal.
    // Returning undefined rather than '' matters: LWC drops an attribute bound
    // to undefined, leaving an <a> with no href - inert, unfocusable, and
    // exactly the right result for a post synced before Post_URL__c existed.
    resolveSocialLink(postUrl) {
        const raw = (postUrl || '').trim();
        return /^https?:\/\//i.test(raw) ? raw : undefined;
    }

    // Loads the newest three synced posts. Apex has already dropped unticked
    // posts; anything with no image borrows a static cover above.
    // The handle rides along from the platform's config metadata, not the post
    // row, so a blank one just means nobody filled it in yet.
    // The three cards the band shipped with before anything was synced. They now
    // double as filler rather than an all-or-nothing alternative: real posts fill
    // the band newest-first and these top it up to three. Held as data instead of
    // markup so both kinds of card go through one rendering path.
    buildFallbackCards() {
        return [
            {
                platform: 'X',
                image: this.communityCoverImg1,
                body: 'Nothing beats reconnecting with familiar faces and shared memories. Milaap brought our alumni back toget...'
            },
            {
                platform: 'Facebook',
                image: this.communityCoverImg2,
                body: 'When leaders return to where it all began. The CXO Meet sparked powerful conve...'
            },
            {
                platform: 'Instagram',
                image: this.communityCoverImg3,
                body: 'If you\'re a Coach or a Creator, and you\'d like to create better videos quickly, check out @TellaHQ'
            }
        ].map((card, index) => ({
            id: `fallback-${index}`,
            body: card.body,
            imageUrl: card.image,
            // No deep link, so the anchor renders without an href and stays inert -
            // there is no original post to open.
            postUrl: undefined,
            handle: FALLBACK_HANDLE,
            hasHandle: true,
            iconUrl: this.resolveSocialIcon(card.platform),
            altText: `${card.platform} post`
        }));
    }

    // Keeps the band at three cards. One or two synced posts is the normal state
    // for weeks after launch, and a row holding a single card reads as a broken
    // layout rather than a feed that is still filling up.
    padToThree(cards) {
        const fallbacks = this.buildFallbackCards();
        const padded = cards.slice(0, SOCIAL_CARD_COUNT);
        while (padded.length < SOCIAL_CARD_COUNT) {
            padded.push(fallbacks[padded.length]);
        }
        return padded;
    }

    loadLandingSocialPosts() {
        // Paint the fallback trio up front so the band never flashes an empty row
        // while the callout is in flight.
        this.landingSocialPosts = this.padToThree([]);

        getLandingSocialPosts()
            .then(records => {
                const list = Array.isArray(records) ? records : [];
                const coverFallbacks = [
                    this.communityCoverImg1,
                    this.communityCoverImg2,
                    this.communityCoverImg3
                ];
                this.landingSocialPosts = this.padToThree(list
                    .map((rec, index) => {
                        const handle = (rec.handle || '').trim();
                        const platform = (rec.platform || '').trim();
                        return {
                            id: rec.id,
                            body: (rec.body || '').trim(),
                            // A post with no usable image keeps its slot and
                            // borrows that slot's existing static cover, so one
                            // imageless post cannot shrink the band to two cards.
                            imageUrl: this.resolveSocialImage(
                                rec.imageUrl,
                                coverFallbacks[index % coverFallbacks.length]
                            ),
                            postUrl: this.resolveSocialLink(rec.postUrl),
                            handle,
                            // No configured handle leaves the card showing just
                            // the logo, rather than an empty span.
                            hasHandle: !!handle,
                            iconUrl: this.resolveSocialIcon(platform),
                            altText: platform ? `${platform} post` : 'Alumni community post'
                        };
                    }));
            })
            .catch(() => {
                // Fall back to the static cards rather than blanking the section.
                this.landingSocialPosts = this.padToThree([]);
            });
    }

    // True once at least one publishable newsletter image exists; until then the
    // section keeps its static cards rather than rendering an empty row.
    get hasLandingNewsletters() {
        return this.landingNewsletters && this.landingNewsletters.length > 0;
    }

    // Loads the flagged newsletter images from the Gallery's "Newsletter" album.
    // Apex has already dropped documents and anything with no public link, so
    // whatever arrives here is renderable; a card is never substituted with a
    // stock cover, which is why the row may hold one or two cards.
    loadLandingNewsletters() {
        getLandingPageNewsletters()
            .then(records => {
                const list = Array.isArray(records) ? records : [];
                this.landingNewsletters = list
                    .map(rec => {
                        const title = (rec.title || '').trim();
                        const dateLabel = (rec.dateLabel || '').trim();
                        return {
                            id: rec.id,
                            title,
                            // No description and no usable file name leaves the
                            // card showing just its date.
                            hasTitle: !!title,
                            dateLabel,
                            imageUrl: this.resolveNewsletterImage(rec.imageUrl),
                            altText: title ? `${title} newsletter` : `${dateLabel} newsletter`
                        };
                    })
                    // Last line of defence: never hand an <img> an unusable src.
                    .filter(rec => !!rec.imageUrl);
            })
            .catch(() => {
                // Fall back to the static cards rather than blanking the section.
                this.landingNewsletters = [];
            });
    }

    // The link is admin-editable free text, so it is shape-checked before being
    // dropped into an <img src>. Returns '' rather than a stock cover when it is
    // unusable, so the card is dropped instead of misrepresenting the file.
    resolveNewsletterImage(imageUrl) {
        const raw = (imageUrl || '').trim();
        return /^(https?:\/\/|\/|data:image\/)/i.test(raw) ? raw : '';
    }

    // Event banner is a free-text field, so only accept something that actually
    // looks like an image URL before dropping it into an inline style.
    buildEventBackground(imageUrl, fallbackImage) {
        const raw = (imageUrl || '').trim();
        const isUsable = /^(https?:\/\/|\/|data:image\/)/i.test(raw) && !/['")]/.test(raw);
        const resolved = isUsable ? raw : (fallbackImage || this.event1);
        return `background-image: url('${resolved}');`;
    }

    // Loads active engagement preferences for the "Make a Difference" cards.
    loadPreferences() {
        getEngagementOptions()
            .then(records => {
                const list = Array.isArray(records) ? records : [];
                this.preferences = list.map(rec => {
                    const icon = rec.iconUrl || '';
                    const isSldsIcon = /^[a-z]+:[a-z0-9_]+$/i.test(icon);
                    const email = (rec.email || '').trim();
                    return {
                        id: rec.id,
                        name: rec.name,
                        description: rec.description,
                        iconUrl: icon,
                        isSldsIcon,
                        isImageIcon: !!icon && !isSldsIcon,
                        email,
                        mailtoHref: email
                            ? `mailto:${email}?subject=${encodeURIComponent(rec.name || 'Enquiry')}`
                            : null
                    };
                });
            })
            .catch(error => {
                console.error('Error loading engagement preferences', error);
                this.preferences = [];
            });
    }
    loadCustomFonts1() {
        const marcellusBasePath = Marcellus_Regular_Font;
        const marcellusUrl = `${marcellusBasePath}/Marcellus-Regular.ttf`;
        const marcellusUrlAlt = `${marcellusBasePath}/marcellusfont/Marcellus-Regular.ttf`;

        const style = document.createElement('style');
        style.innerText = `
          @font-face {
            font-family: 'Marcellus';
            src: url('${marcellusUrl}') format('truetype'),
                 url('${marcellusUrlAlt}') format('truetype');
            font-weight: 400;
            font-style: normal;
            font-display: swap;
          }
          @font-face {
            font-family: 'Marcellus2';
            src: url('${marcellusUrl}') format('truetype'),
                 url('${marcellusUrlAlt}') format('truetype');
            font-weight: 400;
            font-style: normal;
            font-display: swap;
          }
        `;
        document.head.appendChild(style);
      }
    loadCustomFonts() {
        // Load Fira Sans font from static resource
        // Try both paths: with subdirectory and root
        const firaSansBasePath = FIRA_SANS;
        const fontRegularUrl = `${firaSansBasePath}/FiraSans-Regular.woff2`;
        const fontMediumUrl = `${firaSansBasePath}/FiraSans-Medium.woff2`;
        const fontSemiBoldUrl = `${firaSansBasePath}/FiraSans-SemiBold.woff2`;
        const fontBoldUrl = `${firaSansBasePath}/FiraSans-Bold.woff2`;
        const fontExtraBoldUrl = `${firaSansBasePath}/FiraSans-ExtraBold.woff2`;
        
        // Fallback paths if files are in subdirectory
        const fontRegularUrlAlt = `${firaSansBasePath}/FiraSans/FiraSans-Regular.woff2`;
        const fontMediumUrlAlt = `${firaSansBasePath}/FiraSans/FiraSans-Medium.woff2`;
        const fontSemiBoldUrlAlt = `${firaSansBasePath}/FiraSans/FiraSans-SemiBold.woff2`;
        const fontBoldUrlAlt = `${firaSansBasePath}/FiraSans/FiraSans-Bold.woff2`;
        const fontExtraBoldUrlAlt = `${firaSansBasePath}/FiraSans/FiraSans-ExtraBold.woff2`;
        
        const style = document.createElement('style');
        style.innerText = `
            @font-face {
                font-family: "Fira Sans";
                src: url('${fontRegularUrl}') format('woff2'),
                     url('${fontRegularUrlAlt}') format('woff2');
                font-weight: 400;
                font-style: normal;
                font-display: swap;
            }
            @font-face {
                font-family: "Fira Sans";
                src: url('${fontMediumUrl}') format('woff2'),
                     url('${fontMediumUrlAlt}') format('woff2');
                font-weight: 500;
                font-style: normal;
                font-display: swap;
            }
            @font-face {
                font-family: "Fira Sans";
                src: url('${fontSemiBoldUrl}') format('woff2'),
                     url('${fontSemiBoldUrlAlt}') format('woff2');
                font-weight: 600;
                font-style: normal;
                font-display: swap;
            }
            @font-face {
                font-family: "Fira Sans";
                src: url('${fontBoldUrl}') format('woff2'),
                     url('${fontBoldUrlAlt}') format('woff2');
                font-weight: 700;
                font-style: normal;
                font-display: swap;
            }
            @font-face {
                font-family: "Fira Sans";
                src: url('${fontExtraBoldUrl}') format('woff2'),
                     url('${fontExtraBoldUrlAlt}') format('woff2');
                font-weight: 800;
                font-style: normal;
                font-display: swap;
            }
        `;
        document.head.appendChild(style);
    }
    
    disconnectedCallback() {
        if (this.carouselInterval) {
            clearInterval(this.carouselInterval);
        }
    }
    
    get currentImage() {
        return this.carouselImages[this.currentSlide];
    }
    
    get backgroundImageStyle() {
        return `background-image: url('${this.currentImage}'); background-size: cover; background-position: center center; background-repeat: no-repeat;`;
    }
    
    get indicators() {
        return this.carouselImages.map((image, index) => ({
            index: index,
            isActive: this.currentSlide === index,
            cssClass: this.currentSlide === index ? 'indicator active' : 'indicator'
        }));
    }
    
    get event1Background() {
        return `background-image: url('${this.event1}');`;
    }
    
    get event2Background() {
        return `background-image: url('${this.event2}');`;
    }
    
    get event3Background() {
        return `background-image: url('${this.event3}');`;
    }
    
    get event4Background() {
        return `background-image: url('${this.event4}');`;
    }
    
    get ctaBackgroundStyle() {
        return `background-image: url('${this.joinPortalCoverImage}');`;
    }
    
    nextSlide() {
        this.currentSlide = (this.currentSlide + 1) % this.carouselImages.length;
    }
    
    handleIndicatorClick(event) {
        const index = parseInt(event.currentTarget.dataset.index, 10);
        this.goToSlide(index);
    }
    
    goToSlide(index) {
        this.currentSlide = index;
        // Reset auto-rotate timer
        if (this.carouselInterval) {
            clearInterval(this.carouselInterval);
        }
        this.carouselInterval = setInterval(() => {
            this.nextSlide();
        }, 5000);
    }

    handleLogin() {
        // Navigate to login page
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Login'
            }
        });
    }

    handleJoin() {
        // Navigate to registration page
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'Register'
            }
        });
    }

    handleViewAllEvents() {
        // Navigate to events page
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'all_events__c'
            }
        });
    }

    // Footer "Quick Links". These used to just call handleLogin() regardless
    // of label (Giving called a handler that did not even exist), which lost
    // the visitor's intent - Experience Cloud still bounces a guest to Login
    // for a RequiresLogin page, but only navigating to the real named page
    // lets it resume there after the visitor signs in.
    handleFooterEvents() {
        this.handleViewAllEvents();
    }

    handleFooterCommunity() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'network__c'
            }
        });
    }

    handleFooterNewsletter() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'gallery__c'
            }
        });
    }

    handleFooterGiving() {
        this[NavigationMixin.Navigate]({
            type: 'comm__namedPage',
            attributes: {
                name: 'fundraise__c'
            }
        });
    }

    toggleMenu() {
        this.isMenuOpen = !this.isMenuOpen;
    }

    closeMenu() {
        this.isMenuOpen = false;
    }

    handleCloseMap() {
        this.showMapModal = false;
        const container = this.template.querySelector('.landing-page');
        if (container) {
            container.style.overflow = '';
        }
        document.body.style.overflow = '';
    }

    handleMapGuestAction(event) {
        const action = event.detail && event.detail.action;
        this.handleCloseMap();
        if (action === 'register') {
            this.handleJoin();
        } else {
            this.handleLogin();
        }
    }

    stopMapModalClick(event) {
        event.stopPropagation();
    }

    handleNavClick(event) {
        event.preventDefault();
        const target = event.currentTarget.dataset.target;
        // Now that the header stays visible (and clickable) above the
        // full-page map instead of being covered by it, clicking any OTHER
        // header link while the map is open needs to close it first — none
        // of the branches below used to check for this, so the map stayed
        // open (covering the page) no matter what else got clicked.
        if (this.showMapModal && target !== 'map') {
            this.handleCloseMap();
        }
        if (target === 'always') {
            return;
        }
        if (target === 'map') {
            this.closeMenu();
            // Unlike the network/admin map views (which take over the whole
            // viewport), the landing page's real site header must stay
            // visible above the map — so the overlay starts below it instead
            // of at inset:0, and .landing-page (the actual scroll container
            // here, not window/body) is reset to the top so the map always
            // opens from the same place.
            const container = this.template.querySelector('.landing-page');
            if (container) {
                container.scrollTop = 0;
            } else {
                window.scrollTo(0, 0);
            }
            const headerEl = this.template.querySelector('.landing-header');
            const headerHeight = headerEl ? headerEl.getBoundingClientRect().height : 90;
            this.headerOffsetPx = headerHeight;
            this.mapModalHeight = Math.max(420, window.innerHeight - headerHeight);
            this.showMapModal = true;
            if (container) {
                container.style.overflow = 'hidden';
            } else {
                document.body.style.overflow = 'hidden';
            }
            return;
        }
        // For mobile: close menu first, then scroll after DOM updates
        if (this.isMenuOpen) {
            this.closeMenu();
            requestAnimationFrame(() => {
                this.scrollToSection(target);
            });
        } else {
            this.scrollToSection(target);
        }
    }

    scrollToSection(sectionKey) {
        const targetEl = this.template.querySelector(`[data-section="${sectionKey}"]`);
        if (!targetEl) {
            return;
        }
        const header = this.template.querySelector('.landing-header');
        const headerHeight = header ? header.getBoundingClientRect().height : 0;
        // Prefer .landing-page if it scrolls; else try host (when :host has overflow); else window
        const landingPage = this.template.querySelector('.landing-page');
        const container = (landingPage && landingPage.scrollHeight > landingPage.clientHeight)
            ? landingPage
            : (this.scrollHeight > this.clientHeight ? this : null);
        if (container) {
            const containerRect = container.getBoundingClientRect();
            const targetRect = targetEl.getBoundingClientRect();
            const top = (targetRect.top - containerRect.top) + container.scrollTop - headerHeight;
            container.scrollTo({ top: Math.max(0, top), behavior: 'smooth' });
        } else {
            const targetRect = targetEl.getBoundingClientRect();
            const top = targetRect.top + (window.pageYOffset || document.documentElement.scrollTop) - headerHeight;
            window.scrollTo({ top: Math.max(0, top), behavior: 'smooth' });
        }
    }

    get mobileMenuClass() {
        return this.isMenuOpen ? 'mobile-menu active' : 'mobile-menu';
    }

    handleTestimonialsPrev() {
        const cardsContainer = this.template.querySelector('.testimonials-cards');
        if (cardsContainer) {
            const cardWidth = cardsContainer.querySelector('.testimonial-card').offsetWidth;
            const gap = 24; // 1.5rem = 24px
            const scrollAmount = cardWidth + gap;
            cardsContainer.scrollBy({
                left: -scrollAmount,
                behavior: 'smooth'
            });
        }
    }

    handleTestimonialsNext() {
        const cardsContainer = this.template.querySelector('.testimonials-cards');
        if (cardsContainer) {
            const cardWidth = cardsContainer.querySelector('.testimonial-card').offsetWidth;
            const gap = 24; // 1.5rem = 24px
            const scrollAmount = cardWidth + gap;
            cardsContainer.scrollBy({
                left: scrollAmount,
                behavior: 'smooth'
            });
        }
    }

    handleNewsletterPrev() {
        const cardsContainer = this.template.querySelector('.newsletter-cards');
        if (cardsContainer) {
            const cardWidth = cardsContainer.querySelector('.newsletter-card').offsetWidth;
            const gap = 24; // 1.5rem = 24px
            const scrollAmount = cardWidth + gap;
            cardsContainer.scrollBy({
                left: -scrollAmount,
                behavior: 'smooth'
            });
        }
    }

    handleNewsletterNext() {
        const cardsContainer = this.template.querySelector('.newsletter-cards');
        if (cardsContainer) {
            const cardWidth = cardsContainer.querySelector('.newsletter-card').offsetWidth;
            const gap = 24; // 1.5rem = 24px
            const scrollAmount = cardWidth + gap;
            cardsContainer.scrollBy({
                left: scrollAmount,
                behavior: 'smooth'
            });
        }
    }
}
import { LightningElement, api, track } from 'lwc';
import countryFlags from '@salesforce/resourceUrl/CountryFlags';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';
// Country metadata with ISO codes, names, dial codes, and flag file names
const COUNTRIES = [
    { iso: 'in', name: 'India', dialCode: '+91', flagFile: 'in.svg' },
    { iso: 'us', name: 'United States', dialCode: '+1', flagFile: 'us.svg' },
    { iso: 'gb', name: 'United Kingdom', dialCode: '+44', flagFile: 'gb.svg' },
    { iso: 'ca', name: 'Canada', dialCode: '+1', flagFile: 'ca.svg' },
    { iso: 'au', name: 'Australia', dialCode: '+61', flagFile: 'au.svg' },
    { iso: 'de', name: 'Germany', dialCode: '+49', flagFile: 'de.svg' },
    { iso: 'fr', name: 'France', dialCode: '+33', flagFile: 'fr.svg' },
    { iso: 'it', name: 'Italy', dialCode: '+39', flagFile: 'it.svg' },
    { iso: 'es', name: 'Spain', dialCode: '+34', flagFile: 'es.svg' },
    { iso: 'nl', name: 'Netherlands', dialCode: '+31', flagFile: 'nl.svg' },
    { iso: 'be', name: 'Belgium', dialCode: '+32', flagFile: 'be.svg' },
    { iso: 'ch', name: 'Switzerland', dialCode: '+41', flagFile: 'ch.svg' },
    { iso: 'at', name: 'Austria', dialCode: '+43', flagFile: 'at.svg' },
    { iso: 'se', name: 'Sweden', dialCode: '+46', flagFile: 'se.svg' },
    { iso: 'no', name: 'Norway', dialCode: '+47', flagFile: 'no.svg' },
    { iso: 'dk', name: 'Denmark', dialCode: '+45', flagFile: 'dk.svg' },
    { iso: 'fi', name: 'Finland', dialCode: '+358', flagFile: 'fi.svg' },
    { iso: 'pl', name: 'Poland', dialCode: '+48', flagFile: 'pl.svg' },
    { iso: 'ie', name: 'Ireland', dialCode: '+353', flagFile: 'ie.svg' },
    { iso: 'pt', name: 'Portugal', dialCode: '+351', flagFile: 'pt.svg' },
    { iso: 'gr', name: 'Greece', dialCode: '+30', flagFile: 'gr.svg' },
    { iso: 'cz', name: 'Czech Republic', dialCode: '+420', flagFile: 'cz.svg' },
    { iso: 'hu', name: 'Hungary', dialCode: '+36', flagFile: 'hu.svg' },
    { iso: 'ro', name: 'Romania', dialCode: '+40', flagFile: 'ro.svg' },
    { iso: 'bg', name: 'Bulgaria', dialCode: '+359', flagFile: 'bg.svg' },
    { iso: 'hr', name: 'Croatia', dialCode: '+385', flagFile: 'hr.svg' },
    { iso: 'sk', name: 'Slovakia', dialCode: '+421', flagFile: 'sk.svg' },
    { iso: 'si', name: 'Slovenia', dialCode: '+386', flagFile: 'si.svg' },
    { iso: 'ee', name: 'Estonia', dialCode: '+372', flagFile: 'ee.svg' },
    { iso: 'lv', name: 'Latvia', dialCode: '+371', flagFile: 'lv.svg' },
    { iso: 'lt', name: 'Lithuania', dialCode: '+370', flagFile: 'lt.svg' },
    { iso: 'jp', name: 'Japan', dialCode: '+81', flagFile: 'jp.svg' },
    { iso: 'kr', name: 'South Korea', dialCode: '+82', flagFile: 'kr.svg' },
    { iso: 'cn', name: 'China', dialCode: '+86', flagFile: 'cn.svg' },
    { iso: 'sg', name: 'Singapore', dialCode: '+65', flagFile: 'sg.svg' },
    { iso: 'my', name: 'Malaysia', dialCode: '+60', flagFile: 'my.svg' },
    { iso: 'th', name: 'Thailand', dialCode: '+66', flagFile: 'th.svg' },
    { iso: 'ph', name: 'Philippines', dialCode: '+63', flagFile: 'ph.svg' },
    { iso: 'id', name: 'Indonesia', dialCode: '+62', flagFile: 'id.svg' },
    { iso: 'vn', name: 'Vietnam', dialCode: '+84', flagFile: 'vn.svg' },
    { iso: 'nz', name: 'New Zealand', dialCode: '+64', flagFile: 'nz.svg' },
    { iso: 'za', name: 'South Africa', dialCode: '+27', flagFile: 'za.svg' },
    { iso: 'ae', name: 'United Arab Emirates', dialCode: '+971', flagFile: 'ae.svg' },
    { iso: 'sa', name: 'Saudi Arabia', dialCode: '+966', flagFile: 'sa.svg' },
    { iso: 'il', name: 'Israel', dialCode: '+972', flagFile: 'il.svg' },
    { iso: 'tr', name: 'Turkey', dialCode: '+90', flagFile: 'tr.svg' },
    { iso: 'ru', name: 'Russia', dialCode: '+7', flagFile: 'ru.svg' },
    { iso: 'br', name: 'Brazil', dialCode: '+55', flagFile: 'br.svg' },
    { iso: 'mx', name: 'Mexico', dialCode: '+52', flagFile: 'mx.svg' },
    { iso: 'ar', name: 'Argentina', dialCode: '+54', flagFile: 'ar.svg' },
    { iso: 'cl', name: 'Chile', dialCode: '+56', flagFile: 'cl.svg' },
    { iso: 'co', name: 'Colombia', dialCode: '+57', flagFile: 'co.svg' },
    { iso: 'pe', name: 'Peru', dialCode: '+51', flagFile: 'pe.svg' },
    { iso: 've', name: 'Venezuela', dialCode: '+58', flagFile: 've.svg' },
    { iso: 'eg', name: 'Egypt', dialCode: '+20', flagFile: 'eg.svg' },
    { iso: 'ng', name: 'Nigeria', dialCode: '+234', flagFile: 'ng.svg' },
    { iso: 'ke', name: 'Kenya', dialCode: '+254', flagFile: 'ke.svg' },
    { iso: 'gh', name: 'Ghana', dialCode: '+233', flagFile: 'gh.svg' },
    { iso: 'tz', name: 'Tanzania', dialCode: '+255', flagFile: 'tz.svg' },
    { iso: 'ug', name: 'Uganda', dialCode: '+256', flagFile: 'ug.svg' },
    { iso: 'et', name: 'Ethiopia', dialCode: '+251', flagFile: 'et.svg' },
    { iso: 'ma', name: 'Morocco', dialCode: '+212', flagFile: 'ma.svg' },
    { iso: 'dz', name: 'Algeria', dialCode: '+213', flagFile: 'dz.svg' },
    { iso: 'tn', name: 'Tunisia', dialCode: '+216', flagFile: 'tn.svg' },
    { iso: 'ly', name: 'Libya', dialCode: '+218', flagFile: 'ly.svg' },
    { iso: 'sd', name: 'Sudan', dialCode: '+249', flagFile: 'sd.svg' },
    { iso: 'so', name: 'Somalia', dialCode: '+252', flagFile: 'so.svg' },
    { iso: 'dj', name: 'Djibouti', dialCode: '+253', flagFile: 'dj.svg' },
    { iso: 'er', name: 'Eritrea', dialCode: '+291', flagFile: 'er.svg' },
    { iso: 'km', name: 'Comoros', dialCode: '+269', flagFile: 'km.svg' },
    { iso: 'mu', name: 'Mauritius', dialCode: '+230', flagFile: 'mu.svg' },
    { iso: 'sc', name: 'Seychelles', dialCode: '+248', flagFile: 'sc.svg' },
    { iso: 'mg', name: 'Madagascar', dialCode: '+261', flagFile: 'mg.svg' },
    { iso: 'mw', name: 'Malawi', dialCode: '+265', flagFile: 'mw.svg' },
    { iso: 'zm', name: 'Zambia', dialCode: '+260', flagFile: 'zm.svg' },
    { iso: 'zw', name: 'Zimbabwe', dialCode: '+263', flagFile: 'zw.svg' },
    { iso: 'bw', name: 'Botswana', dialCode: '+267', flagFile: 'bw.svg' },
    { iso: 'na', name: 'Namibia', dialCode: '+264', flagFile: 'na.svg' },
    { iso: 'sz', name: 'Eswatini', dialCode: '+268', flagFile: 'sz.svg' },
    { iso: 'ls', name: 'Lesotho', dialCode: '+266', flagFile: 'ls.svg' },
    { iso: 'ao', name: 'Angola', dialCode: '+244', flagFile: 'ao.svg' },
    { iso: 'mz', name: 'Mozambique', dialCode: '+258', flagFile: 'mz.svg' },
    { iso: 'cd', name: 'DR Congo', dialCode: '+243', flagFile: 'cd.svg' },
    { iso: 'cg', name: 'Congo', dialCode: '+242', flagFile: 'cg.svg' },
    { iso: 'cm', name: 'Cameroon', dialCode: '+237', flagFile: 'cm.svg' },
    { iso: 'ci', name: 'Ivory Coast', dialCode: '+225', flagFile: 'ci.svg' },
    { iso: 'sn', name: 'Senegal', dialCode: '+221', flagFile: 'sn.svg' },
    { iso: 'ml', name: 'Mali', dialCode: '+223', flagFile: 'ml.svg' },
    { iso: 'bf', name: 'Burkina Faso', dialCode: '+226', flagFile: 'bf.svg' },
    { iso: 'ne', name: 'Niger', dialCode: '+227', flagFile: 'ne.svg' },
    { iso: 'td', name: 'Chad', dialCode: '+235', flagFile: 'td.svg' },
    { iso: 'cf', name: 'Central African Republic', dialCode: '+236', flagFile: 'cf.svg' },
    { iso: 'ss', name: 'South Sudan', dialCode: '+211', flagFile: 'ss.svg' },
    { iso: 'rw', name: 'Rwanda', dialCode: '+250', flagFile: 'rw.svg' },
    { iso: 'bi', name: 'Burundi', dialCode: '+257', flagFile: 'bi.svg' },
    { iso: 'lr', name: 'Liberia', dialCode: '+231', flagFile: 'lr.svg' },
    { iso: 'sl', name: 'Sierra Leone', dialCode: '+232', flagFile: 'sl.svg' },
    { iso: 'gn', name: 'Guinea', dialCode: '+224', flagFile: 'gn.svg' },
    { iso: 'gw', name: 'Guinea-Bissau', dialCode: '+245', flagFile: 'gw.svg' },
    { iso: 'cv', name: 'Cape Verde', dialCode: '+238', flagFile: 'cv.svg' },
    { iso: 'st', name: 'São Tomé and Príncipe', dialCode: '+239', flagFile: 'st.svg' },
    { iso: 'gq', name: 'Equatorial Guinea', dialCode: '+240', flagFile: 'gq.svg' },
    { iso: 'ga', name: 'Gabon', dialCode: '+241', flagFile: 'ga.svg' },
    { iso: 'eh', name: 'Western Sahara', dialCode: '+212', flagFile: 'eh.svg' },
    { iso: 'mr', name: 'Mauritania', dialCode: '+222', flagFile: 'mr.svg' },
    { iso: 'bj', name: 'Benin', dialCode: '+229', flagFile: 'bj.svg' },
    { iso: 'tg', name: 'Togo', dialCode: '+228', flagFile: 'tg.svg' },
    { iso: 'gm', name: 'Gambia', dialCode: '+220', flagFile: 'gm.svg' },
    { iso: 'af', name: 'Afghanistan', dialCode: '+93', flagFile: 'af.svg' },
    { iso: 'bd', name: 'Bangladesh', dialCode: '+880', flagFile: 'bd.svg' },
    { iso: 'bt', name: 'Bhutan', dialCode: '+975', flagFile: 'bt.svg' },
    { iso: 'mv', name: 'Maldives', dialCode: '+960', flagFile: 'mv.svg' },
    { iso: 'lk', name: 'Sri Lanka', dialCode: '+94', flagFile: 'lk.svg' },
    { iso: 'np', name: 'Nepal', dialCode: '+977', flagFile: 'np.svg' },
    { iso: 'pk', name: 'Pakistan', dialCode: '+92', flagFile: 'pk.svg' },
    { iso: 'ir', name: 'Iran', dialCode: '+98', flagFile: 'ir.svg' },
    { iso: 'iq', name: 'Iraq', dialCode: '+964', flagFile: 'iq.svg' },
    { iso: 'jo', name: 'Jordan', dialCode: '+962', flagFile: 'jo.svg' },
    { iso: 'lb', name: 'Lebanon', dialCode: '+961', flagFile: 'lb.svg' },
    { iso: 'sy', name: 'Syria', dialCode: '+963', flagFile: 'sy.svg' },
    { iso: 'ye', name: 'Yemen', dialCode: '+967', flagFile: 'ye.svg' },
    { iso: 'om', name: 'Oman', dialCode: '+968', flagFile: 'om.svg' },
    { iso: 'qa', name: 'Qatar', dialCode: '+974', flagFile: 'qa.svg' },
    { iso: 'bh', name: 'Bahrain', dialCode: '+973', flagFile: 'bh.svg' },
    { iso: 'kw', name: 'Kuwait', dialCode: '+965', flagFile: 'kw.svg' },
    { iso: 'uz', name: 'Uzbekistan', dialCode: '+998', flagFile: 'uz.svg' },
    { iso: 'kz', name: 'Kazakhstan', dialCode: '+7', flagFile: 'kz.svg' },
    { iso: 'kg', name: 'Kyrgyzstan', dialCode: '+996', flagFile: 'kg.svg' },
    { iso: 'tj', name: 'Tajikistan', dialCode: '+992', flagFile: 'tj.svg' },
    { iso: 'tm', name: 'Turkmenistan', dialCode: '+993', flagFile: 'tm.svg' },
    { iso: 'mn', name: 'Mongolia', dialCode: '+976', flagFile: 'mn.svg' },
    { iso: 'mm', name: 'Myanmar', dialCode: '+95', flagFile: 'mm.svg' },
    { iso: 'la', name: 'Laos', dialCode: '+856', flagFile: 'la.svg' },
    { iso: 'kh', name: 'Cambodia', dialCode: '+855', flagFile: 'kh.svg' },
    { iso: 'bn', name: 'Brunei', dialCode: '+673', flagFile: 'bn.svg' },
    { iso: 'tl', name: 'East Timor', dialCode: '+670', flagFile: 'tl.svg' },
    { iso: 'fj', name: 'Fiji', dialCode: '+679', flagFile: 'fj.svg' },
    { iso: 'pg', name: 'Papua New Guinea', dialCode: '+675', flagFile: 'pg.svg' },
    { iso: 'sb', name: 'Solomon Islands', dialCode: '+677', flagFile: 'sb.svg' },
    { iso: 'vu', name: 'Vanuatu', dialCode: '+678', flagFile: 'vu.svg' },
    { iso: 'nc', name: 'New Caledonia', dialCode: '+687', flagFile: 'nc.svg' },
    { iso: 'pf', name: 'French Polynesia', dialCode: '+689', flagFile: 'pf.svg' },
    { iso: 'ws', name: 'Samoa', dialCode: '+685', flagFile: 'ws.svg' },
    { iso: 'to', name: 'Tonga', dialCode: '+676', flagFile: 'to.svg' },
    { iso: 'ki', name: 'Kiribati', dialCode: '+686', flagFile: 'ki.svg' },
    { iso: 'tv', name: 'Tuvalu', dialCode: '+688', flagFile: 'tv.svg' },
    { iso: 'nr', name: 'Nauru', dialCode: '+674', flagFile: 'nr.svg' },
    { iso: 'pw', name: 'Palau', dialCode: '+680', flagFile: 'pw.svg' },
    { iso: 'fm', name: 'Micronesia', dialCode: '+691', flagFile: 'fm.svg' },
    { iso: 'mh', name: 'Marshall Islands', dialCode: '+692', flagFile: 'mh.svg' },
    { iso: 'ck', name: 'Cook Islands', dialCode: '+682', flagFile: 'ck.svg' },
    { iso: 'nu', name: 'Niue', dialCode: '+683', flagFile: 'nu.svg' },
    { iso: 'tk', name: 'Tokelau', dialCode: '+690', flagFile: 'tk.svg' },
    { iso: 'as', name: 'American Samoa', dialCode: '+1', flagFile: 'as.svg' },
    { iso: 'gu', name: 'Guam', dialCode: '+1', flagFile: 'gu.svg' },
    { iso: 'mp', name: 'Northern Mariana Islands', dialCode: '+1', flagFile: 'mp.svg' },
    { iso: 'vi', name: 'US Virgin Islands', dialCode: '+1', flagFile: 'vi.svg' },
    { iso: 'pr', name: 'Puerto Rico', dialCode: '+1', flagFile: 'pr.svg' },
    { iso: 'do', name: 'Dominican Republic', dialCode: '+1', flagFile: 'do.svg' },
    { iso: 'ht', name: 'Haiti', dialCode: '+509', flagFile: 'ht.svg' },
    { iso: 'jm', name: 'Jamaica', dialCode: '+1', flagFile: 'jm.svg' },
    { iso: 'bb', name: 'Barbados', dialCode: '+1', flagFile: 'bb.svg' },
    { iso: 'tt', name: 'Trinidad and Tobago', dialCode: '+1', flagFile: 'tt.svg' },
    { iso: 'gd', name: 'Grenada', dialCode: '+1', flagFile: 'gd.svg' },
    { iso: 'lc', name: 'Saint Lucia', dialCode: '+1', flagFile: 'lc.svg' },
    { iso: 'vc', name: 'Saint Vincent', dialCode: '+1', flagFile: 'vc.svg' },
    { iso: 'ag', name: 'Antigua and Barbuda', dialCode: '+1', flagFile: 'ag.svg' },
    { iso: 'dm', name: 'Dominica', dialCode: '+1', flagFile: 'dm.svg' },
    { iso: 'kn', name: 'Saint Kitts and Nevis', dialCode: '+1', flagFile: 'kn.svg' },
    { iso: 'bs', name: 'Bahamas', dialCode: '+1', flagFile: 'bs.svg' },
    { iso: 'bz', name: 'Belize', dialCode: '+501', flagFile: 'bz.svg' },
    { iso: 'cr', name: 'Costa Rica', dialCode: '+506', flagFile: 'cr.svg' },
    { iso: 'pa', name: 'Panama', dialCode: '+507', flagFile: 'pa.svg' },
    { iso: 'ni', name: 'Nicaragua', dialCode: '+505', flagFile: 'ni.svg' },
    { iso: 'hn', name: 'Honduras', dialCode: '+504', flagFile: 'hn.svg' },
    { iso: 'sv', name: 'El Salvador', dialCode: '+503', flagFile: 'sv.svg' },
    { iso: 'gt', name: 'Guatemala', dialCode: '+502', flagFile: 'gt.svg' },
    { iso: 'uy', name: 'Uruguay', dialCode: '+598', flagFile: 'uy.svg' },
    { iso: 'py', name: 'Paraguay', dialCode: '+595', flagFile: 'py.svg' },
    { iso: 'bo', name: 'Bolivia', dialCode: '+591', flagFile: 'bo.svg' },
    { iso: 'ec', name: 'Ecuador', dialCode: '+593', flagFile: 'ec.svg' },
    { iso: 'gy', name: 'Guyana', dialCode: '+592', flagFile: 'gy.svg' },
    { iso: 'sr', name: 'Suriname', dialCode: '+597', flagFile: 'sr.svg' },
    { iso: 'gf', name: 'French Guiana', dialCode: '+594', flagFile: 'gf.svg' },
    { iso: 'fk', name: 'Falkland Islands', dialCode: '+500', flagFile: 'fk.svg' },
    { iso: 'gs', name: 'South Georgia', dialCode: '+500', flagFile: 'gs.svg' },
    { iso: 'is', name: 'Iceland', dialCode: '+354', flagFile: 'is.svg' },
    { iso: 'mt', name: 'Malta', dialCode: '+356', flagFile: 'mt.svg' },
    { iso: 'cy', name: 'Cyprus', dialCode: '+357', flagFile: 'cy.svg' },
    { iso: 'lu', name: 'Luxembourg', dialCode: '+352', flagFile: 'lu.svg' },
    { iso: 'li', name: 'Liechtenstein', dialCode: '+423', flagFile: 'li.svg' },
    { iso: 'mc', name: 'Monaco', dialCode: '+377', flagFile: 'mc.svg' },
    { iso: 'ad', name: 'Andorra', dialCode: '+376', flagFile: 'ad.svg' },
    { iso: 'sm', name: 'San Marino', dialCode: '+378', flagFile: 'sm.svg' },
    { iso: 'va', name: 'Vatican City', dialCode: '+39', flagFile: 'va.svg' },
    { iso: 'by', name: 'Belarus', dialCode: '+375', flagFile: 'by.svg' },
    { iso: 'ua', name: 'Ukraine', dialCode: '+380', flagFile: 'ua.svg' },
    { iso: 'md', name: 'Moldova', dialCode: '+373', flagFile: 'md.svg' },
    { iso: 'ge', name: 'Georgia', dialCode: '+995', flagFile: 'ge.svg' },
    { iso: 'am', name: 'Armenia', dialCode: '+374', flagFile: 'am.svg' },
    { iso: 'az', name: 'Azerbaijan', dialCode: '+994', flagFile: 'az.svg' },
    { iso: 'al', name: 'Albania', dialCode: '+355', flagFile: 'al.svg' },
    { iso: 'mk', name: 'North Macedonia', dialCode: '+389', flagFile: 'mk.svg' },
    { iso: 'me', name: 'Montenegro', dialCode: '+382', flagFile: 'me.svg' },
    { iso: 'rs', name: 'Serbia', dialCode: '+381', flagFile: 'rs.svg' },
    { iso: 'ba', name: 'Bosnia and Herzegovina', dialCode: '+387', flagFile: 'ba.svg' },
    { iso: 'xk', name: 'Kosovo', dialCode: '+383', flagFile: 'xk.svg' }
];

export default class KenCustomPhoneInput extends LightningElement {
    _value = ''; // Internal value storage
    @api placeholder = 'Your phone number';
    @api initialCountry = 'in';
    @api required = false;
    @api disabled = false;
    @api label = '';
    @api name = '';
    @api errorMessage = '';

    @track selectedCountry = null;
    @track phoneNumber = ''; // National format
    @track showDropdown = false;
    @track searchQuery = '';
    @track isFocused = false;
    @track isClickingCountrySelector = false;
    
    // Bound event handlers for cleanupx
    boundHandleResize = null;
    boundHandleScroll = null;

    countries = COUNTRIES;
    filteredCountries = COUNTRIES;
    lastRenderedValue = ''; // Track last rendered value to avoid re-parsing

    // Getter/setter for value prop to ensure reactivity
    @api
    get value() {
        return this._value;
    }

    set value(newValue) {
        const oldValue = this._value;
        this._value = newValue || '';
        // If value changed and component is initialized, parse it
        if (oldValue !== this._value && this.selectedCountry) {
            this.parsePhoneNumber(this._value);
        }
    }

    connectedCallback() {
        getPrimaryColor().then(result => {
            document.documentElement.style.setProperty('--primary-color', result.primaryColor);
            document.documentElement.style.setProperty('--secondary-color', result.secondaryColor);
            document.documentElement.style.setProperty('--tertiary-color', result.tertiaryColor);
        }).catch(error => {
            console.error('Error getting primary color:', error);
            console.log('Error getting primary color');
        });

        const country = this.countries.find(c => c.iso === this.initialCountry);
        this.selectedCountry = country || null;
        
        // Parse initial value if provided
        if (this._value) {
            this.parsePhoneNumber(this._value);
        }
        
        // Bind event handlers for window resize and scroll
        this.boundHandleResize = () => {
            if (this.showDropdown) {
                this.updateDropdownPosition();
            }
        };
        this.boundHandleScroll = () => {
            if (this.showDropdown) {
                this.updateDropdownPosition();
            }
        };
        
        // Add event listeners
        window.addEventListener('resize', this.boundHandleResize);
        window.addEventListener('scroll', this.boundHandleScroll, true); // Use capture phase to catch all scrolls
    }
    
    disconnectedCallback() {
        // Clean up event listeners
        if (this.boundHandleResize) {
            window.removeEventListener('resize', this.boundHandleResize);
        }
        if (this.boundHandleScroll) {
            window.removeEventListener('scroll', this.boundHandleScroll, true);
        }
    }

    renderedCallback() {
        // Handle value changes after component is rendered (for prepopulation)
        // This ensures value updates from parent are processed
        if (this._value && this._value !== this.lastRenderedValue) {
            this.parsePhoneNumber(this._value);
            this.lastRenderedValue = this._value;
        }
        // Update dropdown position if it's open (e.g., after window resize or scroll)
        if (this.showDropdown) {
            this.updateDropdownPosition();
        }
    }

    get flagUrl() {
        if (!this.selectedCountry) return '';
        // Use @salesforce/resourceUrl for static resource access
        return `${countryFlags}/flags/${this.selectedCountry.flagFile}`;
    }

    // Fallback flag URL (simple SVG data URI for placeholder)
    get fallbackFlagUrl() {
        return "data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='20' height='15' viewBox='0 0 20 15'%3E%3Crect width='20' height='15' fill='%23ddd'/%3E%3Ctext x='50%25' y='50%25' text-anchor='middle' dy='.3em' font-size='8' fill='%23999'%3E?%3C/text%3E%3C/svg%3E";
    }


    get displayValue() {
        return this.phoneNumber || '';
    }

    get phoneInputWrapperClass() {
        let classes = 'phone-input-wrapper';
        // Add error class when there's an error message (matching registerPage pattern)
        if (this.errorMessage) {
            classes += ' error-state';
        }
        return classes;
    }

    get filteredCountriesList() {
        let countries = this.countries;
        if (this.searchQuery) {
            const query = this.searchQuery.toLowerCase();
            countries = this.countries.filter(country => 
                country.name.toLowerCase().includes(query) ||
                country.dialCode.includes(query) ||
                country.iso.toLowerCase().includes(query)
            );
        }
        // Add flag URL to each country
        // Use @salesforce/resourceUrl for static resource access
        return countries.map(country => ({
            ...country,
            flagUrl: `${countryFlags}/flags/${country.flagFile}`
        }));
    }

    parsePhoneNumber(e164Number) {
        // Simple parsing - extract country code and number
        // This is a basic implementation; you may want to enhance it
        if (!e164Number) {
            this.phoneNumber = '';
            return;
        }

        // Remove spaces from the phone number for parsing
        const cleanedNumber = e164Number.replace(/\s+/g, '');

        if (!cleanedNumber.startsWith('+')) {
            this.phoneNumber = cleanedNumber || '';
            return;
        }

        // Try to match country by dial code (check longest dial codes first)
        const sortedCountries = [...this.countries].sort((a, b) => b.dialCode.length - a.dialCode.length);
        for (const country of sortedCountries) {
            if (cleanedNumber.startsWith(country.dialCode)) {
                this.selectedCountry = country;
                this.phoneNumber = cleanedNumber.substring(country.dialCode.length).trim();
                return;
            }
        }

        // If no match, use default country
        this.phoneNumber = cleanedNumber.substring(1).trim();
    }

    handleInputChange(event) {
        const input = event.target.value.replace(/\D/g, ''); // Remove non-digits
        this.phoneNumber = input;
        // Force the field to reflect the digits-only value immediately. Without this
        // the DOM keeps a typed letter when the stripped value matches the prior state
        // (LWC skips the re-render), so the letter would visibly linger.
        if (event.target.value !== input) {
            event.target.value = input;
        }

        // Clear any error while typing; validation runs only on Register.
        this.errorMessage = '';
        this.setCustomValidity('');

        this.dispatchPhoneChange();
    }

    // Block non-digit characters at the keystroke (covers alphabets/symbols).
    handleKeyPress(event) {
        if (event.key && event.key.length === 1 && !/[0-9]/.test(event.key)) {
            event.preventDefault();
        }
    }

    handleFocus() {
        this.isFocused = true;
    }

    handleBlur(event) {
        this.isFocused = false;
        // Don't close dropdown if clicking on country selector or dropdown
        if (this.isClickingCountrySelector) {
            this.isClickingCountrySelector = false;
            return;
        }
        // Delay closing dropdown to allow click events
        setTimeout(() => {
            // Double check we're not clicking on country selector
            if (!this.isClickingCountrySelector) {
                this.showDropdown = false;
            }
        }, 200);
        // Validation runs only on Register (handleRegister calls validate()), so we
        // don't flag the field on blur / while the user is still filling the form.
    }

    handleCountryClick(event) {
        event.stopPropagation();
        event.preventDefault();
        // Mark that we're clicking on country selector to prevent blur from closing dropdown
        this.isClickingCountrySelector = true;
        const countryIso = event.currentTarget.dataset.countryIso;
        const country = this.countries.find(c => c.iso === countryIso);
        if (!country) return;
        
        this.selectedCountry = country;
        this.showDropdown = false;
        this.searchQuery = '';
        // Clear error when country changes
        if (this.errorMessage) {
            this.errorMessage = '';
            this.setCustomValidity('');
        }
        this.dispatchPhoneChange();
        
        // Reset flag after a short delay
        setTimeout(() => {
            this.isClickingCountrySelector = false;
        }, 300);
        
        // Focus back on input
        const input = this.template.querySelector('.phone-number-input');
        if (input) {
            setTimeout(() => input.focus(), 100);
        }
    }

    handleDropdownToggle(event) {
        if (event) {
            event.stopPropagation();
            event.preventDefault();
            // Mark that we're clicking on country selector to prevent blur from closing dropdown
            this.isClickingCountrySelector = true;
        }
        this.showDropdown = !this.showDropdown;
        if (this.showDropdown) {
            this.searchQuery = '';
            // Calculate dropdown position for fixed positioning
            this.updateDropdownPosition();
            const searchInput = this.template.querySelector('.country-search');
            if (searchInput) {
                setTimeout(() => searchInput.focus(), 100);
            }
        }
        // Reset flag after a short delay
        setTimeout(() => {
            this.isClickingCountrySelector = false;
        }, 300);
    }

    updateDropdownPosition() {
        // Use requestAnimationFrame to ensure DOM is updated before calculating position
        requestAnimationFrame(() => {
            const wrapper = this.template.querySelector('.phone-input-wrapper');
            const dropdown = this.template.querySelector('.country-dropdown');
            if (wrapper && dropdown) {
                const rect = wrapper.getBoundingClientRect();
                // Position dropdown below the input wrapper
                dropdown.style.top = `${rect.bottom + 4}px`; // 4px margin
                dropdown.style.left = `${rect.left}px`;
                dropdown.style.width = `${rect.width}px`;
            }
        });
    }

    handleSearchChange(event) {
        this.searchQuery = event.target.value;
    }

    dispatchPhoneChange() {
        const e164Number = this.getE164Number();
        const event = new CustomEvent('phonechange', {
            detail: {
                e164: e164Number,
                national: this.phoneNumber,
                country: this.selectedCountry,
                isValid: this.isValid()
            },
            bubbles: true,
            composed: true
        });
        this.dispatchEvent(event);
    }

    getE164Number() {
        if (!this.phoneNumber || !this.selectedCountry) {
            return '';
        }
        const cleaned = this.phoneNumber.replace(/\D/g, '');
        // Add space between country code and number for better readability
        return `${this.selectedCountry.dialCode} ${cleaned}`;
    }

    isValid() {
        // If required and empty (check for empty string explicitly), it's invalid
        if (this.required && (!this.phoneNumber || this.phoneNumber.trim() === '')) {
            return false;
        }
        
        // If not required and empty, it's valid
        if (!this.phoneNumber || this.phoneNumber.trim() === '') {
            return true;
        }

        // A number was entered but no country code has been selected
        if (!this.selectedCountry) {
            return false;
        }

        const digits = this.phoneNumber.replace(/\D/g, '');
        
        // Minimum length check
        if (digits.length < 5) {
            return false;
        }
        
        // Country-specific validation
        if (this.selectedCountry) {
            return this.validateCountrySpecific(digits);
        }
        
        // Maximum reasonable length (15 digits per E.164 standard)
        return digits.length <= 15;
    }

    validateCountrySpecific(digits) {
        if (!this.selectedCountry) return true;
        
        const country = this.selectedCountry.iso;
        const length = digits.length;
        
        // Country-specific minimum and maximum lengths
        const countryRules = {
            'in': { min: 10, max: 10 }, // India: 10 digits
            'us': { min: 10, max: 10 }, // US: 10 digits
            'gb': { min: 10, max: 10 }, // UK: 10 digits
            'ca': { min: 10, max: 10 }, // Canada: 10 digits
            'au': { min: 9, max: 9 },   // Australia: 9 digits
            'de': { min: 10, max: 11 }, // Germany: 10-11 digits
            'fr': { min: 9, max: 9 },   // France: 9 digits
            'it': { min: 9, max: 10 },  // Italy: 9-10 digits
            'es': { min: 9, max: 9 },   // Spain: 9 digits
            'nl': { min: 9, max: 9 },   // Netherlands: 9 digits
            'be': { min: 9, max: 9 },   // Belgium: 9 digits
            'ch': { min: 9, max: 9 },   // Switzerland: 9 digits
            'at': { min: 10, max: 13 },  // Austria: 10-13 digits
            'se': { min: 9, max: 9 },   // Sweden: 9 digits
            'no': { min: 8, max: 8 },   // Norway: 8 digits
            'dk': { min: 8, max: 8 },   // Denmark: 8 digits
            'fi': { min: 9, max: 10 },  // Finland: 9-10 digits
            'pl': { min: 9, max: 9 },   // Poland: 9 digits
            'ie': { min: 9, max: 9 },   // Ireland: 9 digits
            'pt': { min: 9, max: 9 },   // Portugal: 9 digits
            'gr': { min: 10, max: 10 }, // Greece: 10 digits
            'cz': { min: 9, max: 9 },   // Czech Republic: 9 digits
            'hu': { min: 9, max: 9 },   // Hungary: 9 digits
            'jp': { min: 10, max: 10 }, // Japan: 10 digits
            'kr': { min: 9, max: 11 },  // South Korea: 9-11 digits
            'cn': { min: 11, max: 11 }, // China: 11 digits
            'sg': { min: 8, max: 8 },   // Singapore: 8 digits
            'my': { min: 9, max: 10 },  // Malaysia: 9-10 digits
            'th': { min: 9, max: 9 },   // Thailand: 9 digits
            'ph': { min: 10, max: 10 }, // Philippines: 10 digits
            'id': { min: 9, max: 11 },  // Indonesia: 9-11 digits
            'vn': { min: 9, max: 10 },  // Vietnam: 9-10 digits
            'nz': { min: 8, max: 10 },  // New Zealand: 8-10 digits
            'za': { min: 9, max: 9 },   // South Africa: 9 digits
            'ae': { min: 9, max: 9 },   // UAE: 9 digits
            'sa': { min: 9, max: 9 },   // Saudi Arabia: 9 digits
            'il': { min: 9, max: 9 },   // Israel: 9 digits
            'tr': { min: 10, max: 10 }, // Turkey: 10 digits
            'ru': { min: 10, max: 10 }, // Russia: 10 digits
            'br': { min: 10, max: 11 }, // Brazil: 10-11 digits
            'mx': { min: 10, max: 10 }, // Mexico: 10 digits
            'ar': { min: 10, max: 10 }, // Argentina: 10 digits
            'cl': { min: 9, max: 9 },   // Chile: 9 digits
            'co': { min: 10, max: 10 }, // Colombia: 10 digits
            'pe': { min: 9, max: 9 },   // Peru: 9 digits
            'eg': { min: 10, max: 10 }, // Egypt: 10 digits
            'ng': { min: 10, max: 11 }, // Nigeria: 10-11 digits
            'ke': { min: 9, max: 9 },   // Kenya: 9 digits
            'gh': { min: 9, max: 9 },   // Ghana: 9 digits
            'pk': { min: 10, max: 10 }, // Pakistan: 10 digits
            'bd': { min: 10, max: 10 }, // Bangladesh: 10 digits
            'np': { min: 10, max: 10 }, // Nepal: 10 digits
            'lk': { min: 9, max: 9 },   // Sri Lanka: 9 digits
        };
        
        const rule = countryRules[country];
        if (rule) {
            return length >= rule.min && length <= rule.max;
        }
        
        // Default: 5-15 digits for countries without specific rules
        return length >= 5 && length <= 15;
    }

    @api
    validate() {
        let isValid = true;
        let message = '';
        
        // Check for empty required field - be explicit about empty string check
        if (this.required && (!this.phoneNumber || this.phoneNumber.trim() === '')) {
            isValid = false;
            message = 'This field cannot be empty.';
        } else if (this.phoneNumber && this.phoneNumber.trim() !== '' && !this.selectedCountry) {
            isValid = false;
            message = 'Please select a country code.';
        } else if (this.phoneNumber && this.phoneNumber.trim() !== '' && !this.isValid()) {
            isValid = false;
            const digits = this.phoneNumber.replace(/\D/g, '');
            
            if (digits.length < 5) {
                message = 'Phone number must be at least 5 digits.';
            } else if (this.selectedCountry) {
                const countryName = this.selectedCountry.name;
                const countryRules = this.getCountryRules(this.selectedCountry.iso);
                
                if (countryRules) {
                    if (digits.length < countryRules.min) {
                        message = `${countryName} phone numbers must be at least ${countryRules.min} digits.`;
                    } else if (digits.length > countryRules.max) {
                        message = `${countryName} phone numbers must be at most ${countryRules.max} digits.`;
                    } else {
                        message = `Please enter a valid ${countryName} phone number.`;
                    }
                } else {
                    message = 'Please enter a valid phone number.';
                }
            } else {
                message = 'Please enter a valid phone number.';
            }
        }
        
        // Use setCustomValidity like registerPage does
        this.setCustomValidity(message);
        this.errorMessage = message; // Keep for display
        
        return isValid;
    }

    setCustomValidity(message) {
        const inputField = this.template.querySelector('[data-id="phone-input"]');
        if (inputField) {
            inputField.setCustomValidity(message);
            // Don't call reportValidity() to avoid showing native browser tooltip
            // Only show custom error message below the field
        }
    }

    getCountryRules(countryIso) {
        const countryRules = {
            'in': { min: 10, max: 10 },
            'us': { min: 10, max: 10 },
            'gb': { min: 10, max: 10 },
            'ca': { min: 10, max: 10 },
            'au': { min: 9, max: 9 },
            'de': { min: 10, max: 11 },
            'fr': { min: 9, max: 9 },
            'it': { min: 9, max: 10 },
            'es': { min: 9, max: 9 },
            'nl': { min: 9, max: 9 },
            'be': { min: 9, max: 9 },
            'ch': { min: 9, max: 9 },
            'at': { min: 10, max: 13 },
            'se': { min: 9, max: 9 },
            'no': { min: 8, max: 8 },
            'dk': { min: 8, max: 8 },
            'fi': { min: 9, max: 10 },
            'pl': { min: 9, max: 9 },
            'ie': { min: 9, max: 9 },
            'pt': { min: 9, max: 9 },
            'gr': { min: 10, max: 10 },
            'cz': { min: 9, max: 9 },
            'hu': { min: 9, max: 9 },
            'jp': { min: 10, max: 10 },
            'kr': { min: 9, max: 11 },
            'cn': { min: 11, max: 11 },
            'sg': { min: 8, max: 8 },
            'my': { min: 9, max: 10 },
            'th': { min: 9, max: 9 },
            'ph': { min: 10, max: 10 },
            'id': { min: 9, max: 11 },
            'vn': { min: 9, max: 10 },
            'nz': { min: 8, max: 10 },
            'za': { min: 9, max: 9 },
            'ae': { min: 9, max: 9 },
            'sa': { min: 9, max: 9 },
            'il': { min: 9, max: 9 },
            'tr': { min: 10, max: 10 },
            'ru': { min: 10, max: 10 },
            'br': { min: 10, max: 11 },
            'mx': { min: 10, max: 10 },
            'ar': { min: 10, max: 10 },
            'cl': { min: 9, max: 9 },
            'co': { min: 10, max: 10 },
            'pe': { min: 9, max: 9 },
            'eg': { min: 10, max: 10 },
            'ng': { min: 10, max: 11 },
            'ke': { min: 9, max: 9 },
            'gh': { min: 9, max: 9 },
            'pk': { min: 10, max: 10 },
            'bd': { min: 10, max: 10 },
            'np': { min: 10, max: 10 },
            'lk': { min: 9, max: 9 },
        };
        return countryRules[countryIso];
    }

    @api
    getValue() {
        return {
            e164: this.getE164Number(),
            national: this.phoneNumber,
            country: this.selectedCountry
        };
    }

    @api
    setValue(e164Number) {
        this.parsePhoneNumber(e164Number);
        this.dispatchPhoneChange();
    }

    handleKeyDown(event) {
        // Allow navigation in dropdown
        if (this.showDropdown && event.key === 'Escape') {
            this.showDropdown = false;
        }
    }

    handleFlagError(event) {
        // Use fallback flag when image fails to load
        if (event.target) {
            event.target.src = this.fallbackFlagUrl;
            event.target.onerror = null; // Prevent infinite loop
        }
    }
}
import { LightningElement, api, track } from 'lwc';
import countryFlags from '@salesforce/resourceUrl/CountryFlags';
import { getPortalConfigs as getPrimaryColor } from 'c/kenThemeConfig';

/* ============================================================================
   Shared country reference + validator.

   These are named exports so the phone fields that DON'T render this component
   — settings, resume builder, guest registration, the job flow, the business
   listing form — can check a number against the same country rules:

       import { validatePhoneNumber } from 'c/kenCustomPhoneInput';

   Keeping them here rather than in a separate module means a country's flag,
   dial code and digit range are declared on one line, in the one place anyone
   edits when a country needs fixing.
   ============================================================================ */

// Fallback range for a country whose entry carries no digit count of its own
// (E.164 caps national numbers at 15).
export const DEFAULT_MIN_DIGITS = 5;
export const DEFAULT_MAX_DIGITS = 15;

export const COUNTRIES = [
    { iso: 'in', name: 'India', dialCode: '+91', flagFile: 'in.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'us', name: 'United States', dialCode: '+1', flagFile: 'us.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'gb', name: 'United Kingdom', dialCode: '+44', flagFile: 'gb.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'ca', name: 'Canada', dialCode: '+1', flagFile: 'ca.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'au', name: 'Australia', dialCode: '+61', flagFile: 'au.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'de', name: 'Germany', dialCode: '+49', flagFile: 'de.svg', minDigits: 10, maxDigits: 11 },
    { iso: 'fr', name: 'France', dialCode: '+33', flagFile: 'fr.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'it', name: 'Italy', dialCode: '+39', flagFile: 'it.svg', minDigits: 9, maxDigits: 10 },
    { iso: 'es', name: 'Spain', dialCode: '+34', flagFile: 'es.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'nl', name: 'Netherlands', dialCode: '+31', flagFile: 'nl.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'be', name: 'Belgium', dialCode: '+32', flagFile: 'be.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ch', name: 'Switzerland', dialCode: '+41', flagFile: 'ch.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'at', name: 'Austria', dialCode: '+43', flagFile: 'at.svg', minDigits: 10, maxDigits: 13 },
    { iso: 'se', name: 'Sweden', dialCode: '+46', flagFile: 'se.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'no', name: 'Norway', dialCode: '+47', flagFile: 'no.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'dk', name: 'Denmark', dialCode: '+45', flagFile: 'dk.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'fi', name: 'Finland', dialCode: '+358', flagFile: 'fi.svg', minDigits: 9, maxDigits: 10 },
    { iso: 'pl', name: 'Poland', dialCode: '+48', flagFile: 'pl.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ie', name: 'Ireland', dialCode: '+353', flagFile: 'ie.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'pt', name: 'Portugal', dialCode: '+351', flagFile: 'pt.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'gr', name: 'Greece', dialCode: '+30', flagFile: 'gr.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'cz', name: 'Czech Republic', dialCode: '+420', flagFile: 'cz.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'hu', name: 'Hungary', dialCode: '+36', flagFile: 'hu.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ro', name: 'Romania', dialCode: '+40', flagFile: 'ro.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'bg', name: 'Bulgaria', dialCode: '+359', flagFile: 'bg.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'hr', name: 'Croatia', dialCode: '+385', flagFile: 'hr.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'sk', name: 'Slovakia', dialCode: '+421', flagFile: 'sk.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'si', name: 'Slovenia', dialCode: '+386', flagFile: 'si.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'ee', name: 'Estonia', dialCode: '+372', flagFile: 'ee.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'lv', name: 'Latvia', dialCode: '+371', flagFile: 'lv.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'lt', name: 'Lithuania', dialCode: '+370', flagFile: 'lt.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'jp', name: 'Japan', dialCode: '+81', flagFile: 'jp.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'kr', name: 'South Korea', dialCode: '+82', flagFile: 'kr.svg', minDigits: 9, maxDigits: 11 },
    { iso: 'cn', name: 'China', dialCode: '+86', flagFile: 'cn.svg', minDigits: 11, maxDigits: 11 },
    { iso: 'sg', name: 'Singapore', dialCode: '+65', flagFile: 'sg.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'my', name: 'Malaysia', dialCode: '+60', flagFile: 'my.svg', minDigits: 9, maxDigits: 10 },
    { iso: 'th', name: 'Thailand', dialCode: '+66', flagFile: 'th.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ph', name: 'Philippines', dialCode: '+63', flagFile: 'ph.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'id', name: 'Indonesia', dialCode: '+62', flagFile: 'id.svg', minDigits: 9, maxDigits: 11 },
    { iso: 'vn', name: 'Vietnam', dialCode: '+84', flagFile: 'vn.svg', minDigits: 9, maxDigits: 10 },
    { iso: 'nz', name: 'New Zealand', dialCode: '+64', flagFile: 'nz.svg', minDigits: 8, maxDigits: 10 },
    { iso: 'za', name: 'South Africa', dialCode: '+27', flagFile: 'za.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ae', name: 'United Arab Emirates', dialCode: '+971', flagFile: 'ae.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'sa', name: 'Saudi Arabia', dialCode: '+966', flagFile: 'sa.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'il', name: 'Israel', dialCode: '+972', flagFile: 'il.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'tr', name: 'Turkey', dialCode: '+90', flagFile: 'tr.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'ru', name: 'Russia', dialCode: '+7', flagFile: 'ru.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'br', name: 'Brazil', dialCode: '+55', flagFile: 'br.svg', minDigits: 10, maxDigits: 11 },
    { iso: 'mx', name: 'Mexico', dialCode: '+52', flagFile: 'mx.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'ar', name: 'Argentina', dialCode: '+54', flagFile: 'ar.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'cl', name: 'Chile', dialCode: '+56', flagFile: 'cl.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'co', name: 'Colombia', dialCode: '+57', flagFile: 'co.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'pe', name: 'Peru', dialCode: '+51', flagFile: 'pe.svg', minDigits: 9, maxDigits: 9 },
    { iso: 've', name: 'Venezuela', dialCode: '+58', flagFile: 've.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'eg', name: 'Egypt', dialCode: '+20', flagFile: 'eg.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'ng', name: 'Nigeria', dialCode: '+234', flagFile: 'ng.svg', minDigits: 10, maxDigits: 11 },
    { iso: 'ke', name: 'Kenya', dialCode: '+254', flagFile: 'ke.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'gh', name: 'Ghana', dialCode: '+233', flagFile: 'gh.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'tz', name: 'Tanzania', dialCode: '+255', flagFile: 'tz.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ug', name: 'Uganda', dialCode: '+256', flagFile: 'ug.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'et', name: 'Ethiopia', dialCode: '+251', flagFile: 'et.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ma', name: 'Morocco', dialCode: '+212', flagFile: 'ma.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'dz', name: 'Algeria', dialCode: '+213', flagFile: 'dz.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'tn', name: 'Tunisia', dialCode: '+216', flagFile: 'tn.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'ly', name: 'Libya', dialCode: '+218', flagFile: 'ly.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'sd', name: 'Sudan', dialCode: '+249', flagFile: 'sd.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'so', name: 'Somalia', dialCode: '+252', flagFile: 'so.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'dj', name: 'Djibouti', dialCode: '+253', flagFile: 'dj.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'er', name: 'Eritrea', dialCode: '+291', flagFile: 'er.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'km', name: 'Comoros', dialCode: '+269', flagFile: 'km.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'mu', name: 'Mauritius', dialCode: '+230', flagFile: 'mu.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'sc', name: 'Seychelles', dialCode: '+248', flagFile: 'sc.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'mg', name: 'Madagascar', dialCode: '+261', flagFile: 'mg.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'mw', name: 'Malawi', dialCode: '+265', flagFile: 'mw.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'zm', name: 'Zambia', dialCode: '+260', flagFile: 'zm.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'zw', name: 'Zimbabwe', dialCode: '+263', flagFile: 'zw.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'bw', name: 'Botswana', dialCode: '+267', flagFile: 'bw.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'na', name: 'Namibia', dialCode: '+264', flagFile: 'na.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'sz', name: 'Eswatini', dialCode: '+268', flagFile: 'sz.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'ls', name: 'Lesotho', dialCode: '+266', flagFile: 'ls.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'ao', name: 'Angola', dialCode: '+244', flagFile: 'ao.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'mz', name: 'Mozambique', dialCode: '+258', flagFile: 'mz.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'cd', name: 'DR Congo', dialCode: '+243', flagFile: 'cd.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'cg', name: 'Congo', dialCode: '+242', flagFile: 'cg.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'cm', name: 'Cameroon', dialCode: '+237', flagFile: 'cm.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ci', name: 'Ivory Coast', dialCode: '+225', flagFile: 'ci.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'sn', name: 'Senegal', dialCode: '+221', flagFile: 'sn.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ml', name: 'Mali', dialCode: '+223', flagFile: 'ml.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'bf', name: 'Burkina Faso', dialCode: '+226', flagFile: 'bf.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'ne', name: 'Niger', dialCode: '+227', flagFile: 'ne.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'td', name: 'Chad', dialCode: '+235', flagFile: 'td.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'cf', name: 'Central African Republic', dialCode: '+236', flagFile: 'cf.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'ss', name: 'South Sudan', dialCode: '+211', flagFile: 'ss.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'rw', name: 'Rwanda', dialCode: '+250', flagFile: 'rw.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'bi', name: 'Burundi', dialCode: '+257', flagFile: 'bi.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'lr', name: 'Liberia', dialCode: '+231', flagFile: 'lr.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'sl', name: 'Sierra Leone', dialCode: '+232', flagFile: 'sl.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'gn', name: 'Guinea', dialCode: '+224', flagFile: 'gn.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'gw', name: 'Guinea-Bissau', dialCode: '+245', flagFile: 'gw.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'cv', name: 'Cape Verde', dialCode: '+238', flagFile: 'cv.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'st', name: 'São Tomé and Príncipe', dialCode: '+239', flagFile: 'st.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'gq', name: 'Equatorial Guinea', dialCode: '+240', flagFile: 'gq.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ga', name: 'Gabon', dialCode: '+241', flagFile: 'ga.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'eh', name: 'Western Sahara', dialCode: '+212', flagFile: 'eh.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'mr', name: 'Mauritania', dialCode: '+222', flagFile: 'mr.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'bj', name: 'Benin', dialCode: '+229', flagFile: 'bj.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'tg', name: 'Togo', dialCode: '+228', flagFile: 'tg.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'gm', name: 'Gambia', dialCode: '+220', flagFile: 'gm.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'af', name: 'Afghanistan', dialCode: '+93', flagFile: 'af.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'bd', name: 'Bangladesh', dialCode: '+880', flagFile: 'bd.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'bt', name: 'Bhutan', dialCode: '+975', flagFile: 'bt.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'mv', name: 'Maldives', dialCode: '+960', flagFile: 'mv.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'lk', name: 'Sri Lanka', dialCode: '+94', flagFile: 'lk.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'np', name: 'Nepal', dialCode: '+977', flagFile: 'np.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'pk', name: 'Pakistan', dialCode: '+92', flagFile: 'pk.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'ir', name: 'Iran', dialCode: '+98', flagFile: 'ir.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'iq', name: 'Iraq', dialCode: '+964', flagFile: 'iq.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'jo', name: 'Jordan', dialCode: '+962', flagFile: 'jo.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'lb', name: 'Lebanon', dialCode: '+961', flagFile: 'lb.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'sy', name: 'Syria', dialCode: '+963', flagFile: 'sy.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ye', name: 'Yemen', dialCode: '+967', flagFile: 'ye.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'om', name: 'Oman', dialCode: '+968', flagFile: 'om.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'qa', name: 'Qatar', dialCode: '+974', flagFile: 'qa.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'bh', name: 'Bahrain', dialCode: '+973', flagFile: 'bh.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'kw', name: 'Kuwait', dialCode: '+965', flagFile: 'kw.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'uz', name: 'Uzbekistan', dialCode: '+998', flagFile: 'uz.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'kz', name: 'Kazakhstan', dialCode: '+7', flagFile: 'kz.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'kg', name: 'Kyrgyzstan', dialCode: '+996', flagFile: 'kg.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'tj', name: 'Tajikistan', dialCode: '+992', flagFile: 'tj.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'tm', name: 'Turkmenistan', dialCode: '+993', flagFile: 'tm.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'mn', name: 'Mongolia', dialCode: '+976', flagFile: 'mn.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'mm', name: 'Myanmar', dialCode: '+95', flagFile: 'mm.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'la', name: 'Laos', dialCode: '+856', flagFile: 'la.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'kh', name: 'Cambodia', dialCode: '+855', flagFile: 'kh.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'bn', name: 'Brunei', dialCode: '+673', flagFile: 'bn.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'tl', name: 'East Timor', dialCode: '+670', flagFile: 'tl.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'fj', name: 'Fiji', dialCode: '+679', flagFile: 'fj.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'pg', name: 'Papua New Guinea', dialCode: '+675', flagFile: 'pg.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'sb', name: 'Solomon Islands', dialCode: '+677', flagFile: 'sb.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'vu', name: 'Vanuatu', dialCode: '+678', flagFile: 'vu.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'nc', name: 'New Caledonia', dialCode: '+687', flagFile: 'nc.svg', minDigits: 6, maxDigits: 6 },
    { iso: 'pf', name: 'French Polynesia', dialCode: '+689', flagFile: 'pf.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'ws', name: 'Samoa', dialCode: '+685', flagFile: 'ws.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'to', name: 'Tonga', dialCode: '+676', flagFile: 'to.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'ki', name: 'Kiribati', dialCode: '+686', flagFile: 'ki.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'tv', name: 'Tuvalu', dialCode: '+688', flagFile: 'tv.svg', minDigits: 6, maxDigits: 6 },
    { iso: 'nr', name: 'Nauru', dialCode: '+674', flagFile: 'nr.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'pw', name: 'Palau', dialCode: '+680', flagFile: 'pw.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'fm', name: 'Micronesia', dialCode: '+691', flagFile: 'fm.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'mh', name: 'Marshall Islands', dialCode: '+692', flagFile: 'mh.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'ck', name: 'Cook Islands', dialCode: '+682', flagFile: 'ck.svg', minDigits: 5, maxDigits: 5 },
    { iso: 'nu', name: 'Niue', dialCode: '+683', flagFile: 'nu.svg', minDigits: 4, maxDigits: 4 },
    { iso: 'tk', name: 'Tokelau', dialCode: '+690', flagFile: 'tk.svg', minDigits: 4, maxDigits: 4 },
    { iso: 'as', name: 'American Samoa', dialCode: '+1', flagFile: 'as.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'gu', name: 'Guam', dialCode: '+1', flagFile: 'gu.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'mp', name: 'Northern Mariana Islands', dialCode: '+1', flagFile: 'mp.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'vi', name: 'US Virgin Islands', dialCode: '+1', flagFile: 'vi.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'pr', name: 'Puerto Rico', dialCode: '+1', flagFile: 'pr.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'do', name: 'Dominican Republic', dialCode: '+1', flagFile: 'do.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'ht', name: 'Haiti', dialCode: '+509', flagFile: 'ht.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'jm', name: 'Jamaica', dialCode: '+1', flagFile: 'jm.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'bb', name: 'Barbados', dialCode: '+1', flagFile: 'bb.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'tt', name: 'Trinidad and Tobago', dialCode: '+1', flagFile: 'tt.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'gd', name: 'Grenada', dialCode: '+1', flagFile: 'gd.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'lc', name: 'Saint Lucia', dialCode: '+1', flagFile: 'lc.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'vc', name: 'Saint Vincent', dialCode: '+1', flagFile: 'vc.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'ag', name: 'Antigua and Barbuda', dialCode: '+1', flagFile: 'ag.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'dm', name: 'Dominica', dialCode: '+1', flagFile: 'dm.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'kn', name: 'Saint Kitts and Nevis', dialCode: '+1', flagFile: 'kn.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'bs', name: 'Bahamas', dialCode: '+1', flagFile: 'bs.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'bz', name: 'Belize', dialCode: '+501', flagFile: 'bz.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'cr', name: 'Costa Rica', dialCode: '+506', flagFile: 'cr.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'pa', name: 'Panama', dialCode: '+507', flagFile: 'pa.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'ni', name: 'Nicaragua', dialCode: '+505', flagFile: 'ni.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'hn', name: 'Honduras', dialCode: '+504', flagFile: 'hn.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'sv', name: 'El Salvador', dialCode: '+503', flagFile: 'sv.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'gt', name: 'Guatemala', dialCode: '+502', flagFile: 'gt.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'uy', name: 'Uruguay', dialCode: '+598', flagFile: 'uy.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'py', name: 'Paraguay', dialCode: '+595', flagFile: 'py.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'bo', name: 'Bolivia', dialCode: '+591', flagFile: 'bo.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'ec', name: 'Ecuador', dialCode: '+593', flagFile: 'ec.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'gy', name: 'Guyana', dialCode: '+592', flagFile: 'gy.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'sr', name: 'Suriname', dialCode: '+597', flagFile: 'sr.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'gf', name: 'French Guiana', dialCode: '+594', flagFile: 'gf.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'fk', name: 'Falkland Islands', dialCode: '+500', flagFile: 'fk.svg', minDigits: 5, maxDigits: 5 },
    { iso: 'gs', name: 'South Georgia', dialCode: '+500', flagFile: 'gs.svg', minDigits: 5, maxDigits: 5 },
    { iso: 'is', name: 'Iceland', dialCode: '+354', flagFile: 'is.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'mt', name: 'Malta', dialCode: '+356', flagFile: 'mt.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'cy', name: 'Cyprus', dialCode: '+357', flagFile: 'cy.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'lu', name: 'Luxembourg', dialCode: '+352', flagFile: 'lu.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'li', name: 'Liechtenstein', dialCode: '+423', flagFile: 'li.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'mc', name: 'Monaco', dialCode: '+377', flagFile: 'mc.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'ad', name: 'Andorra', dialCode: '+376', flagFile: 'ad.svg', minDigits: 6, maxDigits: 6 },
    { iso: 'sm', name: 'San Marino', dialCode: '+378', flagFile: 'sm.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'va', name: 'Vatican City', dialCode: '+39', flagFile: 'va.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'by', name: 'Belarus', dialCode: '+375', flagFile: 'by.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ua', name: 'Ukraine', dialCode: '+380', flagFile: 'ua.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'md', name: 'Moldova', dialCode: '+373', flagFile: 'md.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'ge', name: 'Georgia', dialCode: '+995', flagFile: 'ge.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'am', name: 'Armenia', dialCode: '+374', flagFile: 'am.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'az', name: 'Azerbaijan', dialCode: '+994', flagFile: 'az.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'al', name: 'Albania', dialCode: '+355', flagFile: 'al.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'mk', name: 'North Macedonia', dialCode: '+389', flagFile: 'mk.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'me', name: 'Montenegro', dialCode: '+382', flagFile: 'me.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'rs', name: 'Serbia', dialCode: '+381', flagFile: 'rs.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ba', name: 'Bosnia and Herzegovina', dialCode: '+387', flagFile: 'ba.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'xk', name: 'Kosovo', dialCode: '+383', flagFile: 'xk.svg', minDigits: 8, maxDigits: 8 },
    // Territories and dependencies present in the kenBasicProfile/geoData.js country
    // list that carried no dial code, so a Country of Residence chosen there always
    // resolves to a rule.
    // Rows with no digit count are ones whose national length could not be pinned
    // confidently; they fall back to the E.164 range above rather than guess and
    // reject a real number.
    { iso: 'hk', name: 'Hong Kong', dialCode: '+852', flagFile: 'hk.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'mo', name: 'Macao', dialCode: '+853', flagFile: 'mo.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'tw', name: 'Taiwan', dialCode: '+886', flagFile: 'tw.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'cu', name: 'Cuba', dialCode: '+53', flagFile: 'cu.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'ps', name: 'Palestine', dialCode: '+970', flagFile: 'ps.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'gl', name: 'Greenland', dialCode: '+299', flagFile: 'gl.svg', minDigits: 6, maxDigits: 6 },
    { iso: 'fo', name: 'Faroe Islands', dialCode: '+298', flagFile: 'fo.svg', minDigits: 6, maxDigits: 6 },
    { iso: 'aw', name: 'Aruba', dialCode: '+297', flagFile: 'aw.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'cw', name: 'Curaçao', dialCode: '+599', flagFile: 'cw.svg', minDigits: 7, maxDigits: 7 },
    { iso: 'gi', name: 'Gibraltar', dialCode: '+350', flagFile: 'gi.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'im', name: 'Isle of Man', dialCode: '+44', flagFile: 'im.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'gg', name: 'Guernsey', dialCode: '+44', flagFile: 'gg.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'je', name: 'Jersey', dialCode: '+44', flagFile: 'je.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'sj', name: 'Svalbard and Jan Mayen', dialCode: '+47', flagFile: 'sj.svg', minDigits: 8, maxDigits: 8 },
    { iso: 'ax', name: 'Åland Islands', dialCode: '+358', flagFile: 'ax.svg', minDigits: 9, maxDigits: 10 },
    { iso: 'cc', name: 'Cocos (Keeling) Islands', dialCode: '+61', flagFile: 'cc.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'cx', name: 'Christmas Island', dialCode: '+61', flagFile: 'cx.svg', minDigits: 9, maxDigits: 9 },
    { iso: 're', name: 'Réunion', dialCode: '+262', flagFile: 're.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'yt', name: 'Mayotte', dialCode: '+262', flagFile: 'yt.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'gp', name: 'Guadeloupe', dialCode: '+590', flagFile: 'gp.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'bl', name: 'Saint Barthélemy', dialCode: '+590', flagFile: 'bl.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'mf', name: 'Saint Martin', dialCode: '+590', flagFile: 'mf.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'mq', name: 'Martinique', dialCode: '+596', flagFile: 'mq.svg', minDigits: 9, maxDigits: 9 },
    { iso: 'ai', name: 'Anguilla', dialCode: '+1', flagFile: 'ai.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'bm', name: 'Bermuda', dialCode: '+1', flagFile: 'bm.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'ky', name: 'Cayman Islands', dialCode: '+1', flagFile: 'ky.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'ms', name: 'Montserrat', dialCode: '+1', flagFile: 'ms.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'sx', name: 'Sint Maarten', dialCode: '+1', flagFile: 'sx.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'tc', name: 'Turks and Caicos Islands', dialCode: '+1', flagFile: 'tc.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'vg', name: 'British Virgin Islands', dialCode: '+1', flagFile: 'vg.svg', minDigits: 10, maxDigits: 10 },
    { iso: 'kp', name: 'North Korea', dialCode: '+850', flagFile: 'kp.svg' },
    { iso: 'io', name: 'British Indian Ocean Territory', dialCode: '+246', flagFile: 'io.svg' },
    { iso: 'bq', name: 'Caribbean Netherlands', dialCode: '+599', flagFile: 'bq.svg' },
    { iso: 'sh', name: 'Saint Helena', dialCode: '+290', flagFile: 'sh.svg' },
    { iso: 'pm', name: 'Saint Pierre and Miquelon', dialCode: '+508', flagFile: 'pm.svg' },
    { iso: 'nf', name: 'Norfolk Island', dialCode: '+672', flagFile: 'nf.svg' },
    { iso: 'wf', name: 'Wallis and Futuna', dialCode: '+681', flagFile: 'wf.svg' },
    { iso: 'pn', name: 'Pitcairn Islands', dialCode: '+64', flagFile: 'pn.svg' }
];

const BY_ISO = COUNTRIES.reduce((map, c) => {
    map[c.iso] = c;
    return map;
}, {});

// kenBasicProfile/geoData.js spells 23 countries differently from this list, and
// its spelling is what lands in the stored "Country of Residence" text, so each is
// aliased to the ISO code here — without it a resident of Hong Kong or Timor-Leste
// would get no dial code at all. Verified by joining the two datasets on ISO; every
// other name matches outright.
const GEO_NAME_ALIASES = {
    'aland islands': 'ax',
    'saint-barthelemy': 'bl',
    'bonaire, sint eustatius and saba': 'bq',
    'the bahamas': 'bs',
    'democratic republic of the congo': 'cd',
    'fiji islands': 'fj',
    'the gambia': 'gm',
    'hong kong s.a.r.': 'hk',
    'man (isle of)': 'im',
    'saint-martin (french part)': 'mf',
    'macau s.a.r.': 'mo',
    'pitcairn island': 'pn',
    'palestinian territory occupied': 'ps',
    'reunion': 're',
    'svalbard and jan mayen islands': 'sj',
    'sao tome and principe': 'st',
    'sint maarten (dutch part)': 'sx',
    'timor-leste': 'tl',
    'vatican city state (holy see)': 'va',
    'saint vincent and the grenadines': 'vc',
    'virgin islands (british)': 'vg',
    'virgin islands (us)': 'vi',
    'wallis and futuna islands': 'wf'
};

// Names are matched lowercased so a stored "Country of Residence" text value
// ("India", "india") resolves regardless of how it was captured.
const BY_NAME = COUNTRIES.reduce((map, c) => {
    map[c.name.toLowerCase()] = c;
    return map;
}, {});

Object.keys(GEO_NAME_ALIASES).forEach((alias) => {
    const country = BY_ISO[GEO_NAME_ALIASES[alias]];
    if (country) {
        BY_NAME[alias] = country;
    }
});

export function digitsOnly(value) {
    return String(value == null ? '' : value).replace(/\D/g, '');
}

export function getPhoneCountries() {
    return COUNTRIES;
}

/**
 * Resolves an ISO code, a country name or a dial code to a country row.
 * Dial codes are deliberately NOT resolved here: '+1' and '+590' are each shared
 * by a dozen countries, so a dial code alone cannot pick one and picking the
 * first match would silently validate against the wrong country's digit range.
 */
export function resolveCountry(isoOrName) {
    if (!isoOrName) {
        return null;
    }
    const key = String(isoOrName).trim().toLowerCase();
    return BY_ISO[key] || BY_NAME[key] || null;
}

export function getDigitRange(isoOrName) {
    const country = resolveCountry(isoOrName);
    return {
        min: (country && country.minDigits) || DEFAULT_MIN_DIGITS,
        max: (country && country.maxDigits) || DEFAULT_MAX_DIGITS
    };
}

export function digitRequirementText(isoOrName) {
    const { min, max } = getDigitRange(isoOrName);
    if (min === max) {
        return `${min} digits`;
    }
    return max - min === 1 ? `${min} or ${max} digits` : `${min} to ${max} digits`;
}

/**
 * Splits a stored number into its country and national parts.
 *
 * Longest dial code wins, so '+1 8091234567' (Dominican Republic) is not
 * mistaken for a bare '+1'. Where several countries share the exact dial code
 * the first is returned — enough to drive the digit range, since countries
 * sharing a code share the NANP ten-digit rule.
 */
export function parseE164(value) {
    const raw = String(value == null ? '' : value).trim();
    if (!raw.startsWith('+')) {
        return { country: null, national: digitsOnly(raw) };
    }
    const compact = raw.replace(/\s+/g, '');
    const match = COUNTRIES
        .filter((c) => compact.startsWith(c.dialCode))
        .sort((a, b) => b.dialCode.length - a.dialCode.length)[0];
    if (!match) {
        return { country: null, national: digitsOnly(compact) };
    }
    return { country: match, national: digitsOnly(compact.slice(match.dialCode.length)) };
}

export function formatE164(national, isoOrName) {
    const country = resolveCountry(isoOrName);
    const digits = digitsOnly(national);
    if (!country || !digits) {
        return '';
    }
    return `${country.dialCode} ${digits}`;
}

/**
 * The single validation entry point for phone fields that don't use the
 * kenCustomPhoneInput UI (settings, resume, guest registration, job flow,
 * business listing). Accepts either a full '+CC NNNN' string or a national
 * number plus a country hint.
 *
 * @param {string} value          number as typed, with or without a dial code
 * @param {string} isoOrName      ISO code or country name; used when value carries no dial code
 * @param {boolean} required      whether an empty value is an error
 * @return {{valid: boolean, message: string, e164: string, country: object}}
 */
export function validatePhoneNumber(value, isoOrName, required) {
    const raw = String(value == null ? '' : value).trim();

    if (!raw) {
        return required
            ? { valid: false, message: 'This field cannot be empty.', e164: '', country: null }
            : { valid: true, message: '', e164: '', country: null };
    }

    const parsed = parseE164(raw);
    const country = parsed.country || resolveCountry(isoOrName);
    const national = parsed.country ? parsed.national : digitsOnly(raw);

    if (!country) {
        return { valid: false, message: 'Please select a country code.', e164: '', country: null };
    }

    const { min, max } = getDigitRange(country.iso);
    if (national.length < min || national.length > max) {
        return {
            valid: false,
            message: `${country.name} phone numbers must be ${digitRequirementText(country.iso)}.`,
            e164: '',
            country
        };
    }

    return { valid: true, message: '', e164: `${country.dialCode} ${national}`, country };
}

/* ========================= the component ========================= */

export default class KenCustomPhoneInput extends LightningElement {
    _value = ''; // Internal value storage
    _countryHint = '';
    _userPickedCountry = false;
    @api placeholder = 'Your phone number';
    @api initialCountry = 'in';
    // A country NAME or ISO code from elsewhere on the form — the "Country of
    // Residence" picker fed by geoData, say. Both lists key on ISO 3166-1 alpha-2,
    // so the residence country resolves straight to its dial code and the user
    // doesn't have to set the flag by hand. Only ever a DEFAULT: once a number
    // carrying its own dial code is loaded, or the user picks a flag, that wins,
    // because someone living in Dubai may well keep an Indian mobile.
    @api
    get countryHint() {
        return this._countryHint;
    }

    set countryHint(newHint) {
        this._countryHint = newHint || '';
        // Applied only while the field is still empty and the user hasn't chosen a
        // flag themselves, so changing Country of Residence never rewrites a dial
        // code the user already committed to.
        if (this._userPickedCountry || this.phoneNumber) {
            return;
        }
        const hinted = resolveCountry(this._countryHint);
        if (hinted) {
            this.selectedCountry = hinted;
        }
    }
    @api required = false;
    @api disabled = false;
    @api label = '';
    @api name = '';
    @api errorMessage = '';
    // Border-only error state: red box border without an inline message.
    @api hasError = false;

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

        const hinted = resolveCountry(this.countryHint);
        const country = hinted || this.countries.find(c => c.iso === this.initialCountry);
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
        // or when the parent only wants the red border (has-error).
        if (this.errorMessage || this.hasError) {
            classes += ' error-state';
        }
        return classes;
    }

    get isDisabled() {
        return this.disabled === true || this.disabled === 'true';
    }

    get countrySelectorClass() {
        return this.isDisabled ? 'country-selector disabled' : 'country-selector';
    }

    get isDropdownVisible() {
        return this.showDropdown && !this.isDisabled;
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
        // Alphabetical by country name. slice() first - sorting in place would
        // reorder the shared COUNTRIES array for every instance of this component.
        // Add flag URL to each country
        // Use @salesforce/resourceUrl for static resource access
        return countries
            .slice()
            .sort((a, b) => a.name.localeCompare(b.name))
            .map(country => ({
                ...country,
                flagUrl: `${countryFlags}/flags/${country.flagFile}`
            }));
    }

    parsePhoneNumber(e164Number) {
        // Splitting a stored number back into country + national parts is the same
        // job the plain phone fields do, so it uses the shared parseE164 above rather
        // than reimplementing the dial-code match here.
        if (!e164Number) {
            this.phoneNumber = '';
            return;
        }

        const { country, national } = parseE164(e164Number);
        if (country) {
            this.selectedCountry = country;
        }
        this.phoneNumber = national;
    }

    handleInputChange(event) {
        // Strip non-digits, then cut to the country's maximum so a paste can't push
        // the number past what that country allows.
        const input = event.target.value.replace(/\D/g, '').slice(0, this.digitRange.max);
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
        if (!event.key || event.key.length !== 1) {
            return;
        }
        if (!/[0-9]/.test(event.key)) {
            event.preventDefault();
            return;
        }
        // At the country's maximum an extra digit is dropped, unless the keystroke
        // is replacing a selection.
        const field = event.target;
        const hasSelection = field.selectionStart !== field.selectionEnd;
        if (!hasSelection && field.value.replace(/\D/g, '').length >= this.digitRange.max) {
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
        if (this.isDisabled) {
            return;
        }
        event.stopPropagation();
        event.preventDefault();
        // Mark that we're clicking on country selector to prevent blur from closing dropdown
        this.isClickingCountrySelector = true;
        const countryIso = event.currentTarget.dataset.countryIso;
        const country = this.countries.find(c => c.iso === countryIso);
        if (!country) return;
        // An explicit pick outranks any countryHint pushed in later.
        this._userPickedCountry = true;

        // The new country may allow fewer digits than the old one.
        this.phoneNumber = this.phoneNumber.slice(0, getDigitRange(country.iso).max);
        
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
        if (this.isDisabled) {
            return;
        }
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
            bubbles: true
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

    // How many digits the selected country accepts. The range and the wording
    // below both come from the shared helpers above, so this component and the plain
    // phone fields elsewhere can never disagree about what a country allows.
    get digitRange() {
        return getDigitRange(this.selectedCountry && this.selectedCountry.iso);
    }

    // Caps what the user can type; re-read whenever the country changes.
    get maxDigits() {
        return String(this.digitRange.max);
    }

    // What the error message reads back: "10 digits" for one fixed length,
    // "10 or 11 digits" for two, "10 to 13 digits" for a wider span.
    get digitRequirementText() {
        return digitRequirementText(this.selectedCountry && this.selectedCountry.iso);
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

        const digits = this.phoneNumber.replace(/\D/g, '').length;
        const { min, max } = this.digitRange;
        return digits >= min && digits <= max;
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
            // The requirement is whatever the selected country allows, so the message
            // names that country and its own digit count.
            const countryName = this.selectedCountry ? this.selectedCountry.name : '';
            message = countryName
                ? `${countryName} phone numbers must be ${this.digitRequirementText}.`
                : `Phone number must be ${this.digitRequirementText}.`;
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
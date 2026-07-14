import { LightningElement, api } from 'lwc';

const SELECT_ALL_LABEL = 'Select All',
      ZERO = 0;

export default class eventMultiSelectCombobox extends LightningElement {
    @api placeholder = '';
    showDD = false;
    init = false;
    isExpanded = false;
    isSelectAll = false;
    @api selectedvalues = '';
    @api options = [];


    @api label = 'Select Options';
    @api required = false;
    @api showpills = false;


    renderedCallback() {
        if (!this.init) {
            this.template.querySelector('.cmpl-input').addEventListener('click', (event) => {
                let opts = ZERO;
                if (this.options) {
                    opts = this.options.filter((element) => element.show).length;
                }
                if (this.showDD) {
                    this.showDD = !this.showDD;
                } else {
                    this.showDD = opts > ZERO;
                }
                event.stopPropagation();
            });
            this.template.addEventListener('click', (event) => {
                event.stopPropagation();
            });
            document.addEventListener('click', () => {
                this.showDD = false;
            });
            this.init = true;
        }
    }

    onSearch(event) {
        this.options = this.options.map(option => {
            if (option.label.toLowerCase().startsWith(event.target.value.toLowerCase())) {
                return { ...option, show: true };
            }
            return { ...option, show: false };
        });

        const filteredopts = this.options.filter((element) => element.show);
        this.showDD = filteredopts?.length > ZERO;
    }

    /* eslint-enable max-statements */
    onSelect(event) {                                 
    const { value, checked: isChecked } = event.target; 
    if (value === SELECT_ALL_LABEL) {
        this.options = this.options.map((option) => ({ ...option, checked: isChecked }));
    } else {
        this.options = this.options.map((option) => {
            if (option.value === value) {
                return { ...option, checked: isChecked };
            }
            return option;
        });

        const allSelectedExceptAll = this.options     
            .filter((option) => option.value !== SELECT_ALL_LABEL)
            .every((option) => option.checked);
        this.options = this.options.map((option) => {
            if (option.value === SELECT_ALL_LABEL) {
                return { ...option, checked: allSelectedExceptAll };
            }
            return option;
        });
    }

    this.isSelectAllChecked = this.options.every(    
        (option) => option.checked
    );

    this.postSelect();
    this.sendSelectedOptions();
}

    /* eslint-enable max-statements */

    onRemove(event) {
        const value = event.detail.name;

        this.options = this.options.map(option => {
            if (option.label === value) {
                return { ...option, checked: false };
            }
            return option;
        });

        this.sendSelectedOptions();
        this.postSelect();

    }
    @api
    postSelect() {
        const count = this.options.filter((option) => option.checked).length;
        this.selectedvalues = this.options
            .filter(option => option.checked)
            .map(option => option.label)
            .join(', ');
        if (count > ZERO) {
            this.placeholder = `${count} Item(s) Selected. ${this.selectedvalues}`;
        } else {
            this.placeholder = '';
        }
    }

    sendSelectedOptions() {
    const selectEvent = new CustomEvent('selected', { 
        detail: this.options
            .filter((option) => option.checked)
            .map((option) => option.label)
            .join(';'),
    });
    this.dispatchEvent(selectEvent);
}


    @api validate() {
        const inputField = this.template.querySelector('[data-id="searchInput"]');
         if (this.selectedvalues === '') {
            inputField.setCustomValidity("Please select at least one option");
            inputField.reportValidity();
            return false;
         }
        inputField.setCustomValidity("");
        inputField.reportValidity();
        return true;
     }

}
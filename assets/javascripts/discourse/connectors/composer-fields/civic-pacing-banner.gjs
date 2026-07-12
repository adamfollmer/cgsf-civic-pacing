import Component from "@glimmer/component";
import { tracked } from "@glimmer/tracking";
import { service } from "@ember/service";
import { ajax } from "discourse/lib/ajax";
import { i18n } from "discourse-i18n";

// Shows members their remaining tokens BEFORE they write — rationed
// posting must never waste a member's words.
export default class CivicPacingBanner extends Component {
  @service currentUser;

  @tracked status = null;

  constructor() {
    super(...arguments);
    this.load();
  }

  async load() {
    if (!this.currentUser) {
      return;
    }
    try {
      this.status = await ajax("/civic-pacing/status");
    } catch {
      // no banner is better than a broken composer
    }
  }

  get show() {
    const categoryId = this.args.outletArgs.model?.categoryId;
    return (
      categoryId &&
      this.status &&
      !this.status.exempt &&
      this.status.paced_category_ids.includes(categoryId)
    );
  }

  get line() {
    const creating = this.args.outletArgs.model?.creatingTopic;
    const a = this.status.actions[creating ? "topic" : "reply"];
    const kind = creating ? "topics" : "replies";

    if (a.remaining > 0) {
      return i18n(`civic_pacing.banner.${kind}_left`, {
        count: a.remaining,
        days: a.window_days,
      });
    }

    const hours = Math.max(
      1,
      Math.ceil((new Date(a.next_token_at) - Date.now()) / 3600000)
    );
    return i18n(`civic_pacing.banner.${kind}_none`, { hours });
  }

  <template>
    {{#if this.show}}
      <div class="civic-pacing-banner">{{this.line}}</div>
    {{/if}}
  </template>
}

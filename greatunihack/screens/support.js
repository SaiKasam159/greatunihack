/*
 * Finance Your Friday – standalone screen viewer.
 *
 * The *.dc.html screens were designed on a Claude Design canvas. This small
 * runtime lets each file open on its own in any browser (double-click it),
 * with its buttons, toggles and links between screens still working.
 *
 * Supports the subset of the format the screens use:
 *   {{path}} holes in text and attributes, onClick="{{fn}}" handlers,
 *   <sc-for list as>, <sc-if value>, <dc-import name>, <helmet>,
 *   and a `class Component extends DCLogic` with state / setState / renderVals.
 */
(function () {
  'use strict';

  class DCLogic {
    constructor(props) {
      this.props = props || {};
      this.state = {};
    }
    setState(update) {
      var next = typeof update === 'function' ? update(this.state, this.props) : update;
      this.state = Object.assign({}, this.state, next);
      if (this.__rerender) this.__rerender();
    }
    forceUpdate() {
      if (this.__rerender) this.__rerender();
    }
  }
  window.DCLogic = DCLogic;

  var WHOLE = /^\s*\{\{\s*([^}]+?)\s*\}\}\s*$/;
  var ANY = /\{\{\s*([^}]+?)\s*\}\}/g;

  function lookup(path, scope) {
    path = path.trim();
    if (path === 'true') return true;
    if (path === 'false') return false;
    if (path === 'null') return null;
    if (/^-?\d+(\.\d+)?$/.test(path)) return Number(path);
    if (/^'.*'$|^".*"$/.test(path)) return path.slice(1, -1);
    var parts = path.split('.');
    var value = scope;
    for (var i = 0; i < parts.length; i++) {
      if (value === null || value === undefined) return undefined;
      value = value[parts[i]];
    }
    return value;
  }

  function interpolate(str, scope) {
    return str.replace(ANY, function (_, p) {
      var v = lookup(p, scope);
      return v === null || v === undefined ? '' : String(v);
    });
  }

  function resolveAttr(node, name, scope) {
    var raw = node.getAttribute(name);
    if (raw === null) return undefined;
    var m = WHOLE.exec(raw);
    return m ? lookup(m[1], scope) : interpolate(raw, scope);
  }

  function renderChildren(node, scope, out) {
    var kids = node.childNodes;
    for (var i = 0; i < kids.length; i++) renderNode(kids[i], scope, out);
    return out;
  }

  function renderNode(node, scope, out) {
    if (node.nodeType === 3) {
      out.push(document.createTextNode(interpolate(node.nodeValue, scope)));
      return;
    }
    if (node.nodeType !== 1) return;
    var tag = node.localName;

    if (tag === 'helmet') return;

    if (tag === 'sc-for') {
      var list = resolveAttr(node, 'list', scope) || [];
      var as = node.getAttribute('as') || 'item';
      for (var i = 0; i < list.length; i++) {
        var s = Object.create(scope);
        s[as] = list[i];
        s.$index = i;
        renderChildren(node, s, out);
      }
      return;
    }

    if (tag === 'sc-if') {
      if (resolveAttr(node, 'value', scope)) renderChildren(node, scope, out);
      return;
    }

    if (tag === 'dc-import') {
      var name = node.getAttribute('name');
      var size = (node.getAttribute('hint-size') || '100%,100%').split(',');
      var frame = document.createElement('iframe');
      frame.src = name + '.dc.html';
      frame.title = name;
      frame.setAttribute('tabindex', '-1');
      frame.style.cssText = 'border:0;display:block;pointer-events:none;width:' + size[0].trim() + ';height:' + (size[1] || size[0]).trim();
      out.push(frame);
      return;
    }

    var el = node.namespaceURI && node.namespaceURI !== 'http://www.w3.org/1999/xhtml'
      ? document.createElementNS(node.namespaceURI, node.tagName)
      : document.createElement(tag);

    for (var a = 0; a < node.attributes.length; a++) {
      var attr = node.attributes[a];
      var an = attr.name;
      if (an.indexOf('hint-') === 0) continue;
      var whole = WHOLE.exec(attr.value);
      if (/^on[a-z]+$/i.test(an)) {
        if (whole) {
          (function (fn, evt) {
            if (typeof fn === 'function') el.addEventListener(evt, function (e) { fn(e); });
          })(lookup(whole[1], scope), an.slice(2).toLowerCase());
        }
        continue;
      }
      var value = whole ? lookup(whole[1], scope) : interpolate(attr.value, scope);
      if (value === null || value === undefined || value === false) continue;
      el.setAttribute(an, value === true ? '' : String(value));
    }

    var childOut = renderChildren(node, scope, []);
    for (var c = 0; c < childOut.length; c++) el.appendChild(childOut[c]);
    out.push(el);
  }

  function boot() {
    var root = document.querySelector('x-dc');
    if (!root) return;

    // Hoist <helmet> (fonts, base styles) into <head>.
    var helmet = root.querySelector('helmet');
    if (helmet) {
      Array.prototype.slice.call(helmet.children).forEach(function (child) {
        document.head.appendChild(child.cloneNode(true));
      });
    }

    // Compile the screen's logic class.
    var scriptEl = document.querySelector('script[data-dc-script]');
    var props = {};
    var Component = DCLogic;
    if (scriptEl) {
      try {
        var decl = JSON.parse(scriptEl.getAttribute('data-props') || '{}');
        Object.keys(decl).forEach(function (k) {
          if (k.charAt(0) !== '$' && decl[k] && 'default' in decl[k]) props[k] = decl[k].default;
        });
      } catch (e) { /* no props */ }
      Component = new Function('DCLogic', scriptEl.textContent + '\n;return Component;')(DCLogic);
    }
    var comp = new Component(props);
    if (!comp.state) comp.state = {};

    var template = root.cloneNode(true);
    var mount = document.createElement('div');
    root.parentNode.replaceChild(mount, root);

    var embedded = window.self !== window.top;
    if (!embedded) {
      document.body.style.cssText = 'margin:0;min-height:100vh;display:flex;align-items:center;justify-content:center;background:#E9EBEF;padding:32px 0;box-sizing:border-box';
      mount.style.cssText = 'border-radius:36px;overflow:hidden;box-shadow:0 20px 60px rgba(22,24,29,0.18);flex-shrink:0';
    }

    function rerender() {
      var vals = typeof comp.renderVals === 'function' ? comp.renderVals() : {};
      var nodes = renderChildren(template, vals || {}, []);
      while (mount.firstChild) mount.removeChild(mount.firstChild);
      nodes.forEach(function (n) { mount.appendChild(n); });
    }
    comp.__rerender = rerender;
    rerender();
    if (typeof comp.componentDidMount === 'function') comp.componentDidMount();
  }

  if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', boot);
  else boot();
})();

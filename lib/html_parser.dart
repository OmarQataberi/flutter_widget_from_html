import 'dart:convert';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as parser;
import 'package:url_launcher/url_launcher.dart';

class HtmlParser {
  final String baseUrl;
  final colorHyperlink;
  final BuildContext context;
  final List<double> sizeHeadings;

  final _dataUriRegExp = RegExp(r'^data:.*;base64,');
  var _isParsed = false;
  final List<Widget> _widgets = List();

  HtmlParser({
    this.baseUrl,
    @required this.colorHyperlink,
    @required this.context,
    @required this.sizeHeadings,
  });

  List<Widget> parse(String html) {
    if (_isParsed) {
      return List.unmodifiable(_widgets);
    }

    final document = parser.parse(html);
    _parseElement(document.body);

    _isParsed = true;
    return List.unmodifiable(_widgets);
  }

  TapGestureRecognizer recognizer(String url) {
    return TapGestureRecognizer()
      ..onTap = () async {
        if (await canLaunch(url)) {
          await launch(url);
        }
      };
  }

  _parseElement(dom.Element e) {
    if (e.localName == 'img') {
      _parseElImg(e);
    } else if (_TextParser.canParseElement(e)) {
      _parseTexts(element: e);
    } else {
      List<dom.Node> texts = List();
      e.nodes.forEach((dom.Node node) {
        switch (node.nodeType) {
          case dom.Node.TEXT_NODE:
            texts.add(node);
            break;
          case dom.Node.ELEMENT_NODE:
            if (_TextParser.canParseElement(node)) {
              texts.add(node);
            } else {
              _parseTexts(nodes: texts);
              texts.clear();

              _parseElement(node);
            }
            break;
        }
      });

      // process remaining nodes
      if (texts.length > 0) {
        _parseTexts(nodes: texts);
      }
    }
  }

  _parseElImg(dom.Element e) {
    if (!e.attributes.containsKey('src')) {
      return;
    }

    final src = e.attributes['src'];

    if (src.startsWith("http") || src.startsWith("https")) {
      _widgets.add(new CachedNetworkImage(
        imageUrl: src,
        fit: BoxFit.cover,
      ));
    } else if (src.startsWith('data:image')) {
      final bytes = base64.decode(src.replaceAll(_dataUriRegExp, ''));
      _widgets.add(new Image.memory(bytes, fit: BoxFit.cover));
    } else if (baseUrl != null && baseUrl.isNotEmpty) {
      _widgets.add(new CachedNetworkImage(
        imageUrl: baseUrl + src,
        fit: BoxFit.cover,
      ));
    }
  }

  void _parseTexts({dom.Element element, List<dom.Node> nodes}) {
    final textSpan = _TextParser(this).parse(element: element, nodes: nodes);
    if (textSpan != null) {
      _widgets.add(new RichText(
        softWrap: true,
        text: textSpan,
      ));
    }
  }
}

class _TextParser {
  final HtmlParser p;

  final _attributeStyleRegExp = RegExp(r'([a-zA-Z\-]+)\s*:\s*([^;]*)');
  final List<TextSpan> _children = List();
  final TextStyle _parentStyle;
  TextStyle _style;
  final _spaceRegExp = RegExp(r'(^\s+|\s+$)');
  final _styleColorRegExp = RegExp(r'^#([a-fA-F0-9]{6})$');

  _TextParser(this.p, {TextStyle parentStyle}):
    _parentStyle = parentStyle != null ? parentStyle : DefaultTextStyle.of(p.context).style;

  TextSpan parse({dom.Element element, List<dom.Node> nodes}) {
    assert((element == null) != (nodes == null));
    _style = element != null ? _parseTextStyle(element) : _parentStyle;

    String text = '';
    bool isFirstNode = true;
    final eNodes = element != null ? element.nodes : nodes;
    eNodes.forEach((dom.Node node) {
      switch (node.nodeType) {
        case dom.Node.TEXT_NODE:
          if (isFirstNode) {
            text = node.text.replaceAll(_spaceRegExp, '');
          } else {
            _parseText(node);
          }
          break;
        case dom.Node.ELEMENT_NODE:
          _parseElement(node as dom.Element);
          break;
      }

      isFirstNode = false;
    });

    if (text.isEmpty && _children.length == 0) {
      return null;
    }

    TapGestureRecognizer recognizer;
    if (element != null && element.localName == 'a' && element.attributes.containsKey('href')) {
      recognizer = p.recognizer(element.attributes['href']);
    }

    return TextSpan(
      style: _style,
      children: _children,
      recognizer: recognizer,
      text: text,
    );
  }

  _parseElement(dom.Element e) {
    if (!e.hasContent()) {
      return;
    }

    final textSpan = new _TextParser(p, parentStyle: _style).parse(element: e);
    if (textSpan == null) {
      return;
    }

    _children.add(textSpan);
  }

  _parseText(dom.Node node) {
    String text = node.text;
    if (text == null || text.isEmpty) {
      return;
    }

    _children.add(new TextSpan(text: text));
  }

  TextStyle _parseTextStyle(dom.Element e) {
    var color = _parentStyle.color;
    var decoration = _parentStyle.decoration;
    var fontSize = _parentStyle.fontSize;
    var fontStyle = _parentStyle.fontStyle;
    var fontWeight = _parentStyle.fontWeight;

    switch (e.localName) {
      case 'a':
        decoration = TextDecoration.underline;
        color = p.colorHyperlink;
        break;

      case 'h1':
        fontSize = p.sizeHeadings[0];
        break;
      case 'h2':
        fontSize = p.sizeHeadings[1];
        break;
      case 'h3':
        fontSize = p.sizeHeadings[2];
        break;
      case 'h4':
        fontSize = p.sizeHeadings[3];
        break;
      case 'h5':
        fontSize = p.sizeHeadings[4];
        break;
      case 'h6':
        fontSize = p.sizeHeadings[5];
        break;

      case 'b':
      case 'strong':
        fontWeight = FontWeight.bold;
        break;

      case 'i':
      case 'em':
        fontStyle = FontStyle.italic;
        break;

      case 'u':
        decoration = TextDecoration.underline;
        break;
    }

    if (e.attributes.containsKey('style')) {
      final stylings = _attributeStyleRegExp.allMatches(e.attributes['style']);
      for (final styling in stylings) {
        final param = styling[1].trim();
        final value = styling[2].trim();

        switch (param) {
          case 'color':
            if (this._styleColorRegExp.hasMatch(value)) {
              color = new Color(int.parse('0xFF' + value.replaceAll('#', '').trim()));
            }
            break;

          case 'font-weight':
            switch (value) {
              case 'bold':
                fontWeight = FontWeight.bold;
                break;
              case '100':
                fontWeight = FontWeight.w100;
                break;
              case '200':
                fontWeight = FontWeight.w200;
                break;
              case '300':
                fontWeight = FontWeight.w300;
                break;
              case '400':
                fontWeight = FontWeight.w400;
                break;
              case '500':
                fontWeight = FontWeight.w500;
                break;
              case '600':
                fontWeight = FontWeight.w600;
                break;
              case '700':
                fontWeight = FontWeight.w700;
                break;
              case '800':
                fontWeight = FontWeight.w800;
                break;
              case '900':
                fontWeight = FontWeight.w900;
                break;
            }
            break;

          case 'font-style':
            if (value == 'italic') {
              fontStyle = FontStyle.italic;
            }
            break;

          case 'text-decoration':
            final List<TextDecoration> _textDecorations = List.from([decoration]);
            for (final v in value.split(RegExp(r"\s"))) {
              switch(v) {
                case 'line-through':
                  _textDecorations.add(TextDecoration.lineThrough);
                  break;
                case 'overline':
                  _textDecorations.add(TextDecoration.overline);
                  break;
                case 'underline':
                  _textDecorations.add(TextDecoration.underline);
                  break;
              }
            }
            decoration = TextDecoration.combine(_textDecorations);
            break;
        }
      }
    }

    if (color == _parentStyle.color &&
      decoration == _parentStyle.decoration &&
      fontSize == _parentStyle.fontSize &&
      fontStyle == _parentStyle.fontStyle &&
      fontWeight == _parentStyle.fontWeight
    ) {
      return _parentStyle;
    }

    return TextStyle(
      color: color,
      decoration: decoration,
      fontSize: fontSize,
      fontStyle: fontStyle,
      fontWeight: fontWeight,
    );
  }

  static bool canParseElement(dom.Element e) {
    return !e.outerHtml.contains('<img');
  }
}
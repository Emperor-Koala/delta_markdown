import 'dart:collection';

import 'package:flutter_quill/models/documents/attribute.dart';
import 'package:flutter_quill/models/quill_delta.dart';

import 'src/ast.dart' as ast;

class DeltaVisitor implements ast.NodeVisitor {
  static final _blockTags =
      RegExp('h1|h2|h3|h4|h5|h6|hr|pre|ul|ol|blockquote|p|pre');

  static final _embedTags = RegExp('hr|img');

  Delta delta;

  Queue<Attribute> activeInlineAttributes;
  Attribute activeBlockAttribute;
  Set<String> uniqueIds;

  ast.Element previousElement;
  ast.Element previousToplevelElement;

  Delta convert(List<ast.Node> nodes) {
    delta = Delta();
    activeInlineAttributes = Queue<Attribute>();
    uniqueIds = <String>{};

    for (final node in nodes) {
      node.accept(this);
    }

    // Ensure the delta ends with a newline.
    if (delta.length > 0 && delta.last.value != '\n') {
      delta.insert('\n', activeBlockAttribute?.toJson());
    }

    return delta;
  }

  @override
  void visitText(ast.Text text) {
    // Remove trailing newline
    //final lines = text.text.trim().split('\n');

    /*
    final attributes = Map<String, dynamic>();
    for (final attr in activeInlineAttributes) {
      attributes.addAll(attr.toJson());
    }

    for (final l in lines) {
      delta.insert(l, attributes);
      delta.insert('\n', activeBlockAttribute.toJson());
    }*/

    final str = text.text;
    //if (str.endsWith('\n')) str = str.substring(0, str.length - 1);

    final attributes = <String, dynamic>{};
    for (final attr in activeInlineAttributes) {
      attributes.addAll(attr.toJson());
    }

    var newlineIndex = str.indexOf('\n');
    var startIndex = 0;
    while (newlineIndex != -1) {
      final previousText = str.substring(startIndex, newlineIndex);
      if (previousText.isNotEmpty) {
        delta.insert(previousText, attributes.isNotEmpty ? attributes : null);
      }
      delta.insert('\n', activeBlockAttribute?.toJson());

      startIndex = newlineIndex + 1;
      newlineIndex = str.indexOf('\n', newlineIndex + 1);
    }

    if (startIndex < str.length) {
      final lastStr = str.substring(startIndex);
      delta.insert(lastStr, attributes.isNotEmpty ? attributes : null);
    }
  }

  @override
  bool visitElementBefore(ast.Element element) {
    // Hackish. Separate block-level elements with newlines.
    final attr = _tagToAttribute(element);

    if (delta.isNotEmpty && _blockTags.firstMatch(element.tag) != null) {
      if (element.isToplevel) {
        // If the last active block attribute is not a list, we need to finish
        // it off.
        if (previousToplevelElement.tag != 'ul' &&
            previousToplevelElement.tag != 'ol' &&
            previousToplevelElement.tag != 'pre') {
          delta.insert('\n', activeBlockAttribute?.toJson());
        }

        // Only separate the blocks if both are paragraphs.
        //
        // TODO(kolja): Determine which behavior we really want here.
        // We can either insert an additional newline or just have the
        // paragraphs as single lines. Zefyr will by default render two lines
        // are different paragraphs so for now we will not add an additonal
        // newline here.
        //
        // if (previousToplevelElement != null &&
        //     previousToplevelElement.tag == 'p' &&
        //     element.tag == 'p') {
        //   delta.insert('\n');
        // }
      } else if (element.tag == 'p' &&
          previousElement != null &&
          !previousElement.isToplevel &&
          !previousElement.children.contains(element)) {
        // Here we have two children of the same toplevel element. These need
        // to be separated by additional newlines.

        delta
          // Finish off the last lower-level block.
          ..insert('\n', activeBlockAttribute?.toJson())
          // Add an empty line between the lower-level blocks.
          ..insert('\n', activeBlockAttribute?.toJson());
      }
    }

    // Keep track of the top-level block attribute.
    if (element.isToplevel) {
      activeBlockAttribute = attr;
    }

    if (_embedTags.firstMatch(element.tag) != null) {
      // We write out the element here since the embed has no children or
      // content.
      final kZeroWidthSpace = String.fromCharCode(0x200b);
      delta.insert(kZeroWidthSpace, attr.toJson());
    } else if (_blockTags.firstMatch(element.tag) == null && attr != null) {
      activeInlineAttributes.addLast(attr);
    }

    previousElement = element;
    if (element.isToplevel) {
      previousToplevelElement = element;
    }

    if (element.isEmpty) {
      // Empty element like <hr/>.
      //buffer.write(' />');

      if (element.tag == 'br') {
        delta.insert('\n');
      }

      return false;
    } else {
      //buffer.write('>');
      return true;
    }
  }

  @override
  void visitElementAfter(ast.Element element) {
    if (element.tag == 'li' &&
        (previousToplevelElement.tag == 'ol' ||
            previousToplevelElement.tag == 'ul')) {
      delta.insert('\n', activeBlockAttribute?.toJson());
    }

    final attr = _tagToAttribute(element);
    if (attr == null || !attr.isInline || activeInlineAttributes.last != attr) {
      return;
    }
    activeInlineAttributes.removeLast();

    // Always keep track of the last element.
    // This becomes relevant if we have something like
    //
    // <ul>
    //   <li>...</li>
    //   <li>...</li>
    // </ul>
    previousElement = element;
  }

  /// Uniquifies an id generated from text.
  String uniquifyId(String id) {
    if (!uniqueIds.contains(id)) {
      uniqueIds.add(id);
      return id;
    }

    var suffix = 2;
    var suffixedId = '$id-$suffix';
    while (uniqueIds.contains(suffixedId)) {
      suffixedId = '$id-${suffix++}';
    }
    uniqueIds.add(suffixedId);
    return suffixedId;
  }

  Attribute _tagToAttribute(ast.Element el) {
    switch (el.tag) {
      case 'em':
        return Attribute.italic;
      case 'strong':
        return Attribute.bold;
      case 'ul':
        return Attribute.ul;
      case 'ol':
        return Attribute.ol;
      case 'pre':
        return Attribute.codeBlock;
      case 'blockquote':
        return Attribute.blockQuote;
      case 'h1':
        return Attribute.h1;
      case 'h2':
        return Attribute.h2;
      case 'h3':
        return Attribute.h3;
      case 'a':
        final href = el.attributes['href'];
        return LinkAttribute(href);
      case 'img':
        final href = el.attributes['src'];
        return ImageAttribute(href);
    }

    return null;
  }
}

class ImageAttribute extends Attribute<String> {
  ImageAttribute(String val) : super('image', AttributeScope.EMBEDS, val);
}

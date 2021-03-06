/*
 * Copyright 2013, CZ.NIC z.s.p.o. (http://www.nic.cz/)
 *
 * This file is part of NUCI configuration server.
 *
 * NUCI is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 *  (at your option) any later version.
 *
 * NUCI is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with NUCI.  If not, see <http://www.gnu.org/licenses/>.
 */

#include "cmodel.h"

#include <cstdio>
#include <cassert>

#define CONFIG_URI "http://www.nic.cz/ns/router/uci-raw"

class ConfigModel::Elem {
public:
	virtual QDomElement getNode(QDomDocument &document, bool include_subs, bool get_content, QDomElement *parentNode) const = 0;
	virtual ~Elem() {}
};

class ConfigModel::Option : public Elem {
protected:
	Option(const QDomElement &optionElement, const ConfigModel *model, int order, const Section *s, const QString &val) :
		name(optionElement.namedItem("name").toElement().text()),
		value(val),
		nameIdx(model->createIndex(order, 0, this)),
		valIdx(model->createIndex(order, 1, this)),
		parent(s)
	{}
public:
	const QString name, value;
	const QModelIndex nameIdx, valIdx;
	const Section *parent;
};

class ConfigModel::SimpleOption : public Option {
public:
	SimpleOption(const QDomElement &optionElement, const ConfigModel *model, int order, const Section *s) :
		Option(optionElement, model, order, s, optionElement.namedItem("value").toElement().text())
	{}
	virtual QDomElement getNode(QDomDocument &document, bool include_subs, bool get_content, QDomElement *parentNode) const;
};

class ConfigModel::Value : public Elem {
public:
	Value(const QDomElement &valueElement, const ConfigModel *model, int order, const ListOption *o) :
		name(valueElement.namedItem("index").toElement().text()),
		value(valueElement.namedItem("content").toElement().text()),
		nameIdx(model->createIndex(order, 0, this)),
		valueIdx(model->createIndex(order, 1, this)),
		parent(o)
	{}
	const QString name, value;
	const QModelIndex nameIdx, valueIdx;
	const ListOption *parent;
	virtual QDomElement getNode(QDomDocument &document, bool include_subs, bool get_content, QDomElement *parentNode) const;
};

class ConfigModel::ListOption : public Option {
public:
	ListOption(const QDomElement &optionElement, const ConfigModel *model, int order, const Section *s) :
		Option(optionElement, model, order, s, "")
	{
		const QDomNodeList &valueElems(optionElement.elementsByTagNameNS(CONFIG_URI, "value"));
		for (int i = 0; i < valueElems.count(); i ++)
			values << new Value(valueElems.at(i).toElement(), model, i, this);
	}
	QList<const Value *> values;
	virtual QDomElement getNode(QDomDocument &document, bool include_subs, bool get_content, QDomElement *parentNode) const;
};

class ConfigModel::Section : public Elem {
public:
	Section(const QDomElement &sectionElement, const ConfigModel *model, int order, const ConfigFile *cf) :
		name(sectionElement.namedItem("name").toElement().text()),
		type(sectionElement.namedItem("type").toElement().text()),
		anonymous(!sectionElement.namedItem("anonymous").isNull()),
		nameIdx(model->createIndex(order, 0, this)),
		typeIdx(model->createIndex(order, 1, this)),
		parent(cf)
	{
		const QDomNodeList &children(sectionElement.childNodes());
		for (int i = 0; i < children.count(); i ++) {
			if (!children.at(i).isElement())
				continue;
			const QDomElement &child(children.at(i).toElement());
			const QString &ns(child.namespaceURI());
			if (ns != CONFIG_URI)
				continue;
			const QString &name(child.tagName());
			if (name == "option")
				options << new SimpleOption(child, model, options.count(), this);
			else if (name == "list")
				options << new ListOption(child, model, options.count(), this);
		}
	}
	const QString name, type;
	const bool anonymous;
	const QModelIndex nameIdx, typeIdx;
	const ConfigFile *parent;
	QList<const Option *> options;
	virtual QDomElement getNode(QDomDocument &document, bool include_subs, bool get_content, QDomElement *parentNode) const;
};

class ConfigModel::ConfigFile : public Elem {
public:
	ConfigFile(const QDomElement &configElement, const ConfigModel *model, int order) :
		name(configElement.namedItem("name").toElement().text()),
		index(model->createIndex(order, 0, this)),
		tidx(model->createIndex(order, 1, this))
	{
		const QDomNodeList &sectionElements(configElement.elementsByTagNameNS(CONFIG_URI, "section"));
		for (int i = 0; i < sectionElements.count(); i ++)
			sections << new Section(sectionElements.at(i).toElement(), model, i, this);
	}
	const QString name;
	QList<const Section *> sections;
	const QModelIndex index, tidx;
	virtual QDomElement getNode(QDomDocument &document, bool include_subs, bool, QDomElement *parentNode) const {
		assert(!parentNode);
		QDomNode uci(document.elementsByTagName("uci").at(0));
		QDomElement config(document.createElement("config"));
		QDomElement name(document.createElement("name"));
		QDomText nameText(document.createTextNode(this->name));
		name.appendChild(nameText);
		config.appendChild(name);
		uci.appendChild(config);
		if (include_subs)
			foreach(const Section *s, sections)
				s->getNode(document, true, true, &config);
		return config;
	}
};

QDomElement ConfigModel::Section::getNode(QDomDocument &document, bool include_subs, bool get_content, QDomElement *parentNode) const {
	QDomElement section(document.createElement("section"));
	QDomElement name(document.createElement("name"));
	QDomText nameText(document.createTextNode(this->name));
	name.appendChild(nameText);
	section.appendChild(name);
	if (get_content) {
		QDomElement type(document.createElement("type"));
		QDomText typeText(document.createTextNode(this->type));
		type.appendChild(typeText);
		section.appendChild(type);
		if (anonymous) {
			QDomElement an(document.createElement("anonymous"));
			section.appendChild(an);
		}
	}
	if (include_subs)
		foreach(const Option *opt, options)
			opt->getNode(document, true, true, &section);
	if (parentNode)
		parentNode->appendChild(section);
	else
		parent->getNode(document, false, false, NULL).appendChild(section);
	return section;
}

QDomElement ConfigModel::SimpleOption::getNode(QDomDocument &document, bool, bool get_content, QDomElement *parentNode) const {
	QDomElement option(document.createElement("option"));
	QDomElement name(document.createElement("name"));
	QDomText nameText(document.createTextNode(this->name));
	name.appendChild(nameText);
	option.appendChild(name);
	if (get_content) {
		QDomElement value(document.createElement("value"));
		QDomText valueText(document.createTextNode(this->value));
		value.appendChild(valueText);
		option.appendChild(value);
	}
	if (parentNode)
		parentNode->appendChild(option);
	else
		parent->getNode(document, false, false, NULL).appendChild(option);
	return option;
}

QDomElement ConfigModel::ListOption::getNode(QDomDocument &document, bool include_subs, bool, QDomElement *parentNode) const {
	QDomElement list(document.createElement("list"));
	QDomElement name(document.createElement("name"));
	QDomText nameText(document.createTextNode(this->name));
	name.appendChild(nameText);
	list.appendChild(name);
	if (include_subs)
		foreach(const Value *v, values)
			v->getNode(document, true, true, &list);
	if (parentNode)
		parentNode->appendChild(list);
	else
		parent->getNode(document, false, false, NULL).appendChild(list);
	return list;
}

QDomElement ConfigModel::Value::getNode(QDomDocument &document, bool, bool get_content, QDomElement *parentNode) const {
	QDomElement value(document.createElement("value"));
	QDomElement index(document.createElement("index"));
	QDomText indexText(document.createTextNode(this->name));
	index.appendChild(indexText);
        value.appendChild(index);
	if (get_content) {
		QDomElement content(document.createElement("content"));
		QDomText contentText(document.createTextNode(this->value));
		content.appendChild(contentText);
		value.appendChild(content);
	}
	if (parentNode)
		parentNode->appendChild(value);
	else
		parent->getNode(document, false, false, NULL).appendChild(value);
	return value;
}


ConfigModel::ConfigModel(const QDomDocument &configData_) :
	configData(configData_)
{
	// The namespace trick doesn't neem to work for some reason. OK, whatever.
	const QDomNodeList &configElements(configData.documentElement().elementsByTagNameNS(CONFIG_URI, "config"));
	for (int i = 0; i < configElements.count(); i ++)
		configs << new ConfigFile(configElements.at(i).toElement(), this, i);
}

QModelIndex ConfigModel::index(int row, int column, const QModelIndex &parent) const {
	if (parent.isValid()) {
		const Elem *data = static_cast<const Elem *>(parent.internalPointer());
		const ConfigFile *cf = dynamic_cast<const ConfigFile *>(data);
		const Section *s = dynamic_cast<const Section *>(data);
		const ListOption *l = dynamic_cast<const ListOption *>(data);
		if (cf) {
			const Section *s = cf->sections[row];
			return column ? s->typeIdx : s->nameIdx;
		} else if (s) {
			const Option *o = s->options[row];
			return column ? o->valIdx : o->nameIdx;
		} else if (l) {
			const Value *v = l->values[row];
			return column ? v->valueIdx : v->nameIdx;
		} else
			assert(0);
	} else
		return column ? configs[row]->tidx : configs[row]->index;
}

QModelIndex ConfigModel::parent(const QModelIndex &index) const {
	const Elem *data = static_cast<const Elem *>(index.internalPointer());
	const ConfigFile *cf = dynamic_cast<const ConfigFile *>(data);
	if (cf)
		return QModelIndex();
	const Section *s = dynamic_cast<const Section *>(data);
	if (s)
		return s->parent->index;
	const Option *o = dynamic_cast<const Option *>(data);
	if (o)
		return o->parent->nameIdx;
	const Value *v = dynamic_cast<const Value *>(data);
	if (v)
		return v->parent->nameIdx;
	assert(0);
}

int ConfigModel::rowCount(const QModelIndex &parent) const {
	if (parent.isValid()) {
		const Elem *data = static_cast<const Elem *>(parent.internalPointer());
		const ConfigFile *cf = dynamic_cast<const ConfigFile *>(data);
		const Section *s = dynamic_cast<const Section *>(data);
		const ListOption *l = dynamic_cast<const ListOption *>(data);
		if (cf)
			return cf->sections.size();
		else if (s)
			return s->options.size();
		else if (l)
			return l->values.size();
		else
			return 0;
	} else
		return configs.size();
}

int ConfigModel::columnCount(const QModelIndex &parent) const {
	if (parent.isValid()) {
		const Elem *data = static_cast<const Elem *>(parent.internalPointer());
		const ConfigFile *cf = dynamic_cast<const ConfigFile *>(data);
		const Section *s = dynamic_cast<const Section *>(data);
		const ListOption *l = dynamic_cast<const ListOption *>(data);
		if (cf || s || l)
			return 2;
		else
			return 0;
	} else
		return 2;
}

QVariant ConfigModel::data(const QModelIndex &index, int role) const {
	const Elem *data = static_cast<const Elem *>(index.internalPointer());
	const ConfigFile *cf = dynamic_cast<const ConfigFile *>(data);
	const Section *s = dynamic_cast<const Section *>(data);
	const Option *o = dynamic_cast<const Option *>(data);
	const Value *v = dynamic_cast<const Value *>(data);
	switch (role) {
		case Qt::DisplayRole:
			if (cf)
				return index.column() ? "config" : cf->name;
			if (s)
				return index.column() ? s->type : s->name;
			if (o)
				return index.column() ? o->value : o->name;
			if (v)
				return index.column() ? v->value : v->name;
		case Qt::DecorationRole:
			if (index.column())
				return QVariant();
			if (cf)
				return Qt::yellow;
			if (s)
				return Qt::red;
			if (v || dynamic_cast<const SimpleOption *>(data))
				return Qt::blue;
			if (o)
				return Qt::green;
		default:
			return QVariant();
	}
}

QVariant ConfigModel::headerData(int section, Qt::Orientation orientation, int role) const {
	if (orientation != Qt::Horizontal || role != Qt::DisplayRole)
		return QVariant();
	return section ? "type/value" : "name";
}

QDomElement ConfigModel::getNode(const QModelIndex &index, QDomDocument &document, bool include_subs, bool get_content) const {
	const Elem *data = static_cast<const Elem *>(index.internalPointer());
	return data->getNode(document, include_subs, get_content, NULL);
}

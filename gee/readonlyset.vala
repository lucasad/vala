/* readonlyset.vala
 *
 * Copyright (C) 2007-2008  Jürg Billeter
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public
 * License as published by the Free Software Foundation; either
 * version 2.1 of the License, or (at your option) any later version.

 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.

 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301  USA
 *
 * Author:
 * 	Jürg Billeter <j@bitron.ch>
 */

using GLib;

/**
 * Represents a read-only collection of items without duplicates.
 */
public class Gee.ReadOnlySet<G> : Object, Iterable<G>, Collection<G>, Set<G> {
	public int size {
		get { return _set.size; }
	}

	public Set<G> set {
		set { _set = value; }
	}

	private Set<G> _set;

	public ReadOnlySet (construct Set<G> set = null) {
	}

	public Type get_element_type () {
		return typeof (G);
	}

	public Gee.Iterator<G> iterator () {
		if (_set == null) {
			return new Iterator<G> ();
		}

		return _set.iterator ();
	}

	public bool contains (G item) {
		if (_set == null) {
			return false;
		}

		return _set.contains (item);
	}

	public bool add (G item) {
		assert_not_reached ();
		return false;
	}

	public bool remove (G item) {
		assert_not_reached ();
		return false;
	}

	public void clear () {
		assert_not_reached ();
	}

	private class Iterator<G> : Object, Gee.Iterator<G> {
		public bool next () {
			return false;
		}

		public G get () {
			return null;
		}
	}
}

